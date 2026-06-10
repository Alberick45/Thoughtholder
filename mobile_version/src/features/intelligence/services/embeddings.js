// Initialize the singleton WebWorker process
let workerInstance = null;

function getWorker() {
  if (!workerInstance) {
    workerInstance = new Worker(new URL('../workers/embeddings.worker.js', import.meta.url), { type: 'module' });
  }
  return workerInstance;
}

/**
 * Generate a 384-dimensional Float32Array embedding for a given string without blocking UI
 */
export function generateEmbedding(text) {
  return new Promise((resolve) => {
    try {
      const worker = getWorker();
      const id = Math.random().toString();
      
      const messageHandler = (e) => {
        if (e.data.id === id) {
          worker.removeEventListener('message', messageHandler);
          if (e.data.status === 'complete') {
            resolve(e.data.vector);
          } else {
            console.error("Vector generation inside worker failed:", e.data.error);
            resolve(null);
          }
        }
      };
      
      worker.addEventListener('message', messageHandler);
      worker.postMessage({ text, id });
      
    } catch (err) {
      console.error("Failed to post message to vector worker:", err);
      resolve(null);
    }
  });
}

/**
 * Calculates Cosine Similarity between two numeric arrays
 */
export function cosineSimilarity(vecA, vecB) {
  if (!vecA || !vecB || vecA.length !== vecB.length) return 0;
  let dotProduct = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < vecA.length; i++) {
    dotProduct += vecA[i] * vecB[i];
    normA += vecA[i] * vecA[i];
    normB += vecB[i] * vecB[i];
  }
  if (normA === 0 || normB === 0) return 0;
  return dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
}
