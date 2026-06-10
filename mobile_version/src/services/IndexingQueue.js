import { generateEmbedding } from '../features/intelligence/services/embeddings';
import { SemanticChunker } from '../core/utils/SemanticChunker';

/**
 * Background Indexing Queue
 * Decouples note saving from the heavy embedding generation process.
 * In a real Capacitor app, this could also interface with Android WorkManager
 * via a native plugin if the app needs to index while closed.
 */
class IndexingQueueService {
    constructor() {
        this.queue = [];
        this.isProcessing = false;
        this.chunker = new SemanticChunker(200, 30);
    }

    /**
     * Set the database reference
     */
    setDb(dbStore) {
        this.dbStore = dbStore;
    }

    /**
     * Enqueue a note to be processed and embedded in the background
     */
    enqueue(thoughtId, text) {
        this.queue.push({ thoughtId, text });
        console.log(`[IndexingQueue] Job queued for thought ${thoughtId}. Queue size: ${this.queue.length}`);
        
        if (!this.isProcessing) {
            this.processQueue();
        }
    }

    async processQueue() {
        if (this.queue.length === 0) {
            this.isProcessing = false;
            return;
        }

        this.isProcessing = true;
        const job = this.queue.shift();

        try {
            console.log(`[IndexingQueue] Processing thought ${job.thoughtId}...`);
            
            // 1. Semantic Chunking
            const chunks = this.chunker.chunk(job.text);
            
            // For simplicity in a 1-to-1 schema we embed the first major chunk,
            // or average them. A true RAG system stores 1 row per chunk.
            // If the schema `thoughts` is 1-to-1, we will average the chunk embeddings.
            
            if (chunks.length > 0) {
                let sumVector = new Array(384).fill(0);
                let validChunks = 0;
                
                for (const chunk of chunks) {
                    const vector = await generateEmbedding(chunk);
                    if (vector && vector.length === 384) {
                        for (let i = 0; i < 384; i++) {
                            sumVector[i] += vector[i];
                        }
                        validChunks++;
                    }
                }
                
                if (validChunks > 0) {
                    // Average and normalize
                    let norm = 0;
                    for (let i = 0; i < 384; i++) {
                        sumVector[i] /= validChunks;
                        norm += sumVector[i] * sumVector[i];
                    }
                    norm = Math.sqrt(norm);
                    for (let i = 0; i < 384; i++) {
                        sumVector[i] /= norm; // unit vector
                    }
                    
                    if (this.dbStore) {
                        await this.dbStore.updateEmbedding(job.thoughtId, sumVector);
                        console.log(`[IndexingQueue] Thought ${job.thoughtId} embedded and saved to sqlite-vec.`);
                    }
                }
            }

        } catch (error) {
            console.error(`[IndexingQueue] Failed to process thought ${job.thoughtId}`, error);
            // Optionally requeue or save to a dead-letter table
        }

        // Process next item
        // Use setTimeout to yield back to the main JS thread so UI stays 60fps
        setTimeout(() => this.processQueue(), 100);
    }
}

export const IndexingQueue = new IndexingQueueService();
