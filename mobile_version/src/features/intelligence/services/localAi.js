/**
 * Local AI Service for Mobile (APK) / Offline Use
 * Uses WASM-based Transformers.js to run models directly in the browser/app.
 */

let generator = null;
let modelName = 'Xenova/Qwen1.5-0.5B-Chat'; // Extremely lightweight for mobile

export async function initLocalAI() {
  if (generator) return generator;

  console.log('[LOCAL AI] Initializing WASM Engine...');
  try {
    const mod = await import('@xenova/transformers');
    const pipe = mod.pipeline || mod.default?.pipeline || mod.default || mod;
    const env = mod.env || mod.default?.env;

    if (env) {
       env.allowLocalModels = false;
    }

    if (typeof pipe !== 'function') {
      console.error('[LOCAL AI] Pipeline resolver failed. mod type:', typeof mod, 'pipe type:', typeof pipe);
      // Fallback: try default export again with extreme caution
      if (mod.default && typeof mod.default === 'function') {
         generator = await mod.default('text-generation', modelName, { device: 'wasm' });
         console.log('[LOCAL AI] Engine Ready (via default func).');
         return generator;
      }
      throw new Error("Local AI Pipeline function not found in module exports.");
    }

    generator = await pipe('text-generation', modelName, {
      device: 'wasm', // Force WASM for broad compatibility
    });
    console.log('[LOCAL AI] Engine Ready. Model:', modelName);
    return generator;
  } catch (err) {
    console.error('[LOCAL AI] Initialization Failed:', err);
    throw err;
  }
}

export async function askLocalAI(prompt, systemPrompt = '') {
  try {
    const gen = await initLocalAI();

    const formattedPrompt = `<|im_start|>system\n${systemPrompt}<|im_end|>\n<|im_start|>user\n${prompt}<|im_end|>\n<|im_start|>assistant\n`;

    const output = await gen(formattedPrompt, {
      max_new_tokens: 256, 
      temperature: 0.3,    
      repetition_penalty: 1.2,
      do_sample: true
    });

    const fullText = output[0].generated_text;
    const parts = fullText.split('<|im_start|>assistant\n');
    let cleaned = parts.length > 1 ? parts.pop() : fullText;

    cleaned = cleaned.replace('<|im_end|>', '')
      .replace(/<\|im_start\|>system[\s\S]*?<\|im_end\|>/gi, '')
      .replace(/<\|im_start\|>user[\s\S]*?<\|im_end\|>/gi, '')
      .trim();

    return cleaned;
  } catch (err) {
    console.error('[LOCAL AI] askLocalAI Failed:', err);
    throw err;
  }
}
