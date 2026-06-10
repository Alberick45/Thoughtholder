-- Schema for local RAG thoughts using sqlite-vec
-- Ensure sqlite-vec extension is loaded before executing

CREATE TABLE IF NOT EXISTS thoughts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    text TEXT NOT NULL,
    
    -- In sqlite-vec, embeddings are typically stored in a separate virtual table,
    -- or stored as BLOB in the main table and indexed in a vec0 virtual table.
    -- We will store the raw embedding here for completeness, and link it to a vec table.
    embedding BLOB,
    
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    
    importance REAL DEFAULT 1.0,
    access_count INTEGER DEFAULT 0,
    
    tags TEXT,
    source TEXT
);

-- sqlite-vec virtual table for fast cosine similarity search
-- Assumes 384 dimensions for all-MiniLM-L6-v2
CREATE VIRTUAL TABLE IF NOT EXISTS vec_thoughts USING vec0(
    thought_id INTEGER PRIMARY KEY,
    embedding float[384]
);

-- Trigger to keep virtual table synced with main table (optional, or handle in app logic)
-- Since we handle embedding separately via a background queue, we'll insert into vec_thoughts 
-- programmatically when the embedding is ready.
