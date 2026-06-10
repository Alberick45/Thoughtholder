/**
 * VectorStore
 * Handles storage and retrieval of thoughts using sqlite-vec.
 * Supports hybrid ranking (Semantic Similarity + Recency + Importance).
 */

export class VectorStore {
    constructor(db) {
        // Assume 'db' is a connection wrapper capable of executing SQL queries
        // and loading the sqlite-vec extension.
        this.db = db;
    }

    /**
     * Initializes the schema
     */
    async initialize() {
        const schema = `
            CREATE TABLE IF NOT EXISTS thoughts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                text TEXT NOT NULL,
                embedding BLOB,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                importance REAL DEFAULT 1.0,
                access_count INTEGER DEFAULT 0,
                tags TEXT,
                source TEXT
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS vec_thoughts USING vec0(
                thought_id INTEGER PRIMARY KEY,
                embedding float[384]
            );
        `;
        await this.db.execute(schema);
    }

    /**
     * Inserts a new thought without an embedding (fast path)
     * The embedding will be generated and updated later by the background worker.
     */
    async insertThought(text, tags = '', source = 'user') {
        const now = Date.now();
        const res = await this.db.run(
            `INSERT INTO thoughts (text, created_at, updated_at, importance, tags, source) 
             VALUES (?, ?, ?, ?, ?, ?)`,
            [text, now, now, 1.0, tags, source]
        );
        return res.lastInsertId;
    }

    /**
     * Updates a thought with its vector embedding.
     */
    async updateEmbedding(thoughtId, embeddingArray) {
        // embeddingArray should be a Float32Array or standard array of length 384
        const blob = new Float32Array(embeddingArray).buffer;

        // Update main table
        await this.db.run(`UPDATE thoughts SET embedding = ?, updated_at = ? WHERE id = ?`, [blob, Date.now(), thoughtId]);
        
        // Insert or replace into vec0 table
        await this.db.run(`INSERT OR REPLACE INTO vec_thoughts(thought_id, embedding) VALUES (?, ?)`, [thoughtId, blob]);
    }

    /**
     * Hybrid Search Query
     * Combines vector similarity with recency and importance using SQLite query logic.
     */
    async search(queryVector, limit = 5) {
        const queryBlob = new Float32Array(queryVector).buffer;
        
        // Base query using sqlite-vec distance metric
        // Note: vec_distance returns euclidean or cosine depending on setup, 
        // smaller is closer if distance, larger if cosine. We assume vec_distance is distance, 
        // so similarity = 1 - distance (roughly, if normalized).
        
        const sql = `
            WITH vector_matches AS (
                SELECT 
                    thought_id,
                    (1.0 - vec_distance_cosine(embedding, ?)) AS semantic_similarity
                FROM vec_thoughts
                WHERE embedding MATCH ? AND k = 100 -- fetch broad pool for reranking
            )
            SELECT 
                t.id,
                t.text,
                t.created_at,
                t.importance,
                v.semantic_similarity,
                -- Recency calculation (decay over time)
                -- Max 1.0 for now(), approaching 0 for older items
                EXP(-CAST((? - t.updated_at) AS REAL) / 86400000.0) AS recency_score,
                
                -- Hybrid scoring formula:
                (0.70 * v.semantic_similarity) + 
                (0.20 * EXP(-CAST((? - t.updated_at) AS REAL) / 86400000.0)) + 
                (0.10 * t.importance) AS final_score
            FROM thoughts t
            JOIN vector_matches v ON t.id = v.thought_id
            ORDER BY final_score DESC
            LIMIT ?
        `;

        const now = Date.now();
        // The parameters matching the `?`
        // 1: queryBlob (for cosine similarity)
        // 2: queryBlob (for match)
        // 3: now (for recency)
        // 4: now (for recency inside formula)
        // 5: limit
        const results = await this.db.query(sql, [queryBlob, queryBlob, now, now, limit]);
        
        return results;
    }

    async incrementAccessCount(id) {
        await this.db.run(`UPDATE thoughts SET access_count = access_count + 1 WHERE id = ?`, [id]);
    }
}
