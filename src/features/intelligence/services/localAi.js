import { pipeline, env } from '@xenova/transformers';

/**
 * Local AI Service for Mobile (APK) / Offline Use
 * Uses WASM-based Transformers.js to run models directly in the browser/app.
 */

// Configure environment for local assets if needed
env.allowLocalModels = false; // Set to true if bundling models in assets

let generator = null;
let modelName = 'Xenova/Qwen1.5-0.5B-Chat'; // Extremely lightweight for mobile

export async function initLocalAI() {
  if (generator) return generator;
  
  console.log('[LOCAL AI] Initializing WASM Engine...');
  try {
    generator = await pipeline('text-generation', modelName, {
      device: 'wasm', // Force WASM for broad compatibility
    });
    console.log('[LOCAL AI] Engine Ready.');
    return generator;
  } catch (err) {
    console.error('[LOCAL AI] Initialization Failed:', err);
    throw err;
  }
}

export async function askLocalAI(prompt, systemPrompt = '') {
  const gen = await initLocalAI();
  
  const formattedPrompt = `<|im_start|>system\n${systemPrompt}<|im_end|>\n<|im_start|>user\n${prompt}<|im_end|>\n<|im_start|>assistant\n`;
  
  const output = await gen(formattedPrompt, {
    max_new_tokens: 256, // Increased for better local depth
    temperature: 0.3,    // Reduced for stability
    repetition_penalty: 1.2,
    do_sample: true
  });

  const fullText = output[0].generated_text;
  // Robust extraction: find the LAST occurrence of the assistant start tag
  const parts = fullText.split('<|im_start|>assistant\n');
  let cleaned = parts.length > 1 ? parts.pop() : fullText;
  
  // Final sanitization
  cleaned = cleaned.replace('<|im_end|>', '')
                   .replace(/<\|im_start\|>system[\s\S]*?<\|im_end\|>/gi, '')
                   .replace(/<\|im_start\|>user[\s\S]*?<\|im_end\|>/gi, '')
                   .trim();
                   
  return cleaned;
}
