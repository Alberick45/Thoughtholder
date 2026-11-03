import sys
import sqlite3
import os

def run_db_checks(db_path):
    if not os.path.exists(db_path):
        print(f"[FAIL] Database file copy does not exist: {db_path}")
        return False

    all_passed = True

    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        # 1. PRAGMA integrity_check
        cursor.execute("PRAGMA integrity_check;")
        integrity = cursor.fetchone()
        if integrity and integrity[0] == "ok":
            print("[PASS] SQLite PRAGMA integrity_check: ok")
        else:
            print(f"[FAIL] SQLite PRAGMA integrity_check failed: {integrity}")
            all_passed = False

        # 2. Schema: required tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = {row[0] for row in cursor.fetchall()}
        required_tables = {"thoughts", "buckets", "deleted_records", "bucket_aliases"}
        missing_tables = required_tables - tables
        if not missing_tables:
            print(f"[PASS] Schema tables verified: {len(tables)} tables present")
        else:
            print(f"[FAIL] Missing schema tables: {missing_tables}")
            all_passed = False

        # 3. Performance indexes
        cursor.execute("SELECT name FROM sqlite_master WHERE type='index';")
        indexes = {row[0] for row in cursor.fetchall()}
        required_indexes = {
            "idx_thoughts_bucket",
            "idx_thoughts_status_done",
            "idx_thoughts_created_at",
            "idx_thoughts_trashed",
        }
        missing_indexes = required_indexes - indexes
        if not missing_indexes:
            print("[PASS] Performance indexes: all 4 indexes present")
        else:
            print(f"[FAIL] Missing indexes: {missing_indexes}")
            all_passed = False

        # 4. Thought ID uniqueness
        cursor.execute("SELECT COUNT(DISTINCT id), COUNT(*) FROM thoughts;")
        unique_ids, total_ids = cursor.fetchone()
        if unique_ids == total_ids:
            print(f"[PASS] Thought ID uniqueness: {unique_ids}/{total_ids} distinct")
        else:
            print(f"[FAIL] Duplicate or empty IDs detected: {unique_ids} unique vs {total_ids} total")
            all_passed = False

        # 5. Orphaned bucket references
        cursor.execute("""
            SELECT COUNT(DISTINCT bucket) FROM thoughts 
            WHERE bucket IS NOT NULL 
              AND trim(bucket) != '' 
              AND bucket NOT IN (SELECT name FROM buckets);
        """)
        orphaned = cursor.fetchone()[0]
        if orphaned == 0:
            print("[PASS] Folder consistency: 0 orphaned bucket references")
        else:
            print(f"[FAIL] Orphaned bucket references found: {orphaned} unknown folders referenced")
            all_passed = False

        # 6. Count arithmetic (live + done + trash = total)
        cursor.execute("SELECT COUNT(*) FROM thoughts WHERE trashed = 0 AND (done = 0 AND status != 'done');")
        live = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM thoughts WHERE trashed = 0 AND (done = 1 OR status = 'done');")
        done = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM thoughts WHERE trashed = 1;")
        trashed = cursor.fetchone()[0]

        sum_parts = live + done + trashed
        if sum_parts == total_ids:
            print(f"[PASS] Idea count arithmetic: Live({live}) + Done({done}) + Trash({trashed}) = Total({total_ids})")
        else:
            print(f"[FAIL] Idea count arithmetic mismatch: {sum_parts} != {total_ids}")
            all_passed = False

        conn.close()
    except Exception as e:
        print(f"[FAIL] Unexpected error inspecting database copy: {e}")
        return False

    return all_passed

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python check_db.py <path_to_db_copy>")
        sys.exit(1)

    success = run_db_checks(sys.argv[1])
    sys.exit(0 if success else 1)
