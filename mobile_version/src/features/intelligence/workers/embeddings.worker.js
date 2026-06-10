import { pipeline, env } from '@xenova/transformers';

// Configure environment to prevent Vite from intercepting model requests with 404/index.html
env.allowLocalModels = false;
env.useBrowserCache = true;
// Enforce mobile thread limits for embedding (1-2 threads max)
env.backends.onnx.wasm.numThreads = 2;

class VectorPipeline {
  static task = 'feature-extraction';
  static model = 'Xenova/all-MiniLM-L6-v2';
  static instance = null;

  static async getInstance(progress_callback = null) {
    if (this.instance === null) {
      this.instance = await pipeline(this.task, this.model, { progress_callback });
    }
    return this.instance;
  }
}

// Map to handle multiple simultaneous requests
self.addEventListener('message', async (e) => {
  const { text, id } = e.data;
  
  try {
    const extractor = await VectorPipeline.getInstance();
    const output = await extractor(text, { pooling: 'mean', normalize: true });
    
    // Send back the pure array payload
    self.postMessage({ id, status: 'complete', vector: Array.from(output.data) });
  } catch (err) {
    self.postMessage({ id, status: 'error', error: err.message });
  }
});
