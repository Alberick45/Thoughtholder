#!/usr/bin/env python3
import sys
import os
import hashlib
import json
import argparse

def compute_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest().lower()

def main():
    parser = argparse.ArgumentParser(description="Generate version.json for ThoughtHolder release")
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', type=int, required=True)
    parser.add_argument('--min-build', type=int, default=1)
    parser.add_argument('--apk', required=True)
    parser.add_argument('--setup-exe', required=True)
    parser.add_argument('--notes-file', default='RELEASE_NOTES.md')
    parser.add_argument('--repo', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    notes = []
    if os.path.exists(args.notes_file):
        with open(args.notes_file, 'r', encoding='utf-8') as f:
            for line in f:
                s = line.strip()
                if s.startswith('- ') or s.startswith('* '):
                    notes.append(s[2:].strip())
    if not notes:
        notes = ["General improvements and bug fixes"]

    apk_sha = compute_sha256(args.apk)
    win_sha = compute_sha256(args.setup_exe)

    apk_name = os.path.basename(args.apk)
    win_name = os.path.basename(args.setup_exe)

    manifest = {
        "version": args.version,
        "build": args.build,
        "minSupportedBuild": args.min_build,
        "notes": notes,
        "android": {
            "url": f"https://github.com/{args.repo}/releases/download/v{args.version}/{apk_name}",
            "sha256": apk_sha
        },
        "windows": {
            "url": f"https://github.com/{args.repo}/releases/download/v{args.version}/{win_name}",
            "sha256": win_sha
        }
    }

    out_dir = os.path.dirname(args.output)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(manifest, f, indent=2)

    print(f"Generated {args.output} successfully:")
    print(json.dumps(manifest, indent=2))

if __name__ == '__main__':
    main()

