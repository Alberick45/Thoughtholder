/**
 * JAOS Model Router
 * Routes cognitive tasks to specialized models to optimize latency and hardware load.
 */

import { bus } from './CognitiveEventBus';

export const ModelTiers = {
    TIER_1_AMBIENT: 'phi3:latest',              // Tiny model. Fast, emotional detection, tags.
    TIER_2_DIALOGUE: 'llama3:latest',           // Medium model. General chat, reactive OS.
    TIER_3_HEAVY: 'qwen2.5-coder:14b'           // Large model. Complex planning, deep focus.
};

export class ModelRouter {
    constructor(baseUrl = 'http://127.0.0.1:11434') {
        this.baseUrl = baseUrl;
    }

    /**
     * Core Inference Gateway
     */
    async route(messages, options = {}) {
        const tier = options.tier || ModelTiers.TIER_2_DIALOGUE;
        
        bus.publish('MODEL_STATUS', { model: tier, status: 'INFERENCE' });

        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 30000); // 30s timeout

        try {
            const response = await fetch(`${this.baseUrl}/api/chat`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                signal: controller.signal,
                body: JSON.stringify({
                    model: tier,
                    messages: messages,
                    stream: false,
                    options: {
                        num_predict: options.maxTokens || 800, // Increased from 200 for depth
                        temperature: options.temperature || 0.6,
                        num_ctx: options.contextWindow || 4096 // Keep context tight
                    }
                })
            });
            clearTimeout(timeoutId);

            if (!response.ok) {
                // Fallback Escalation
                console.warn(`[ROUTER] Tier ${tier} failed. Status: ${response.status}. Falling back to standard Tier 2.`);
                return this.fallbackRoute(messages, options);
            }

            const data = await response.json();
            bus.publish('MODEL_STATUS', { model: tier, status: 'IDLE' });
            return data.message.content;

        } catch (error) {
            console.warn(`[ROUTER] Fetch failed for ${tier}. Attempting Local Fallback...`, error);
            try {
                // Check if running in native mobile environment
                const { Capacitor, registerPlugin } = await import('@capacitor/core');
                if (Capacitor.isNativePlatform()) {
                    console.log('[ROUTER] Using Native Llama.cpp Engine for offline generation.');
                    const Llama = registerPlugin('Llama');
                    
                    // Extract last user message for local AI
                    const userMsg = messages.filter(m => m.role === 'user').pop()?.content || 'Hello';
                    const systemMsg = 'You are an intelligent mobile assistant.';
                    const fullPrompt = `<|im_start|>system\\n${systemMsg}<|im_end|>\\n<|im_start|>user\\n${userMsg}<|im_end|>\\n<|im_start|>assistant\\n`;
                    
                    return new Promise((resolve, reject) => {
                        let finalResponse = '';
                        Llama.generateTokenStream({ prompt: fullPrompt }, (data, err) => {
                            if (err) {
                                reject(err);
                                return;
                            }
                            if (data.done) {
                                resolve(finalResponse.trim());
                            } else {
                                finalResponse += data.token;
                                // In a fully reactive UI, we'd fire an event here to stream tokens
                                // bus.publish('LLM_TOKEN', { token: data.token });
                            }
                        });
                    });
                } else {
                    console.log('[ROUTER] Not native platform. Attempting WASM Fallback...');
                    const { askLocalAI } = await import('../services/localAi');
                    const userMsg = messages.filter(m => m.role === 'user').pop()?.content || 'Hello';
                    return await askLocalAI(userMsg, 'You are Jarvis (Local Fallback).');
                }
            } catch (localErr) {
                bus.publish('MODEL_STATUS', { model: tier, status: 'ERROR', error: error.message });
                throw error;
            }
        }
    }

    async fallbackRoute(messages, options) {
        if (options.isFallback) throw new Error("Ollama Fallback Failed. Make sure you have the standard 'llama3' and 'phi3' models installed.");
        // Attempt with stable Tier 2 dialogue model
        options.tier = ModelTiers.TIER_2_DIALOGUE;
        options.contextWindow = 2048; // Reduce context for safety
        options.isFallback = true;
        return this.route(messages, options);
    }

    /**
     * Specialized Route: Ambient Emotion & State Analysis
     * Uses Tier 1 (Phi-3 Mini) for extreme low-latency background checks.
     */
    async analyzeAmbientState(prompt) {
        return this.route([{ role: 'user', content: prompt }], { 
            tier: ModelTiers.TIER_1_AMBIENT,
            maxTokens: 50,
            temperature: 0.1, // Highly deterministic
            contextWindow: 1024 // Tiny window for speed
        });
    }

    /**
     * Specialized Route: Deep Strategic Reflection
     * Uses Tier 3 (Qwen 14B) for complex, high-latency planning.
     */
    async deepFocus(prompt) {
        return this.route([{ role: 'user', content: prompt }], {
            tier: ModelTiers.TIER_3_HEAVY,
            maxTokens: 1500, // Increased from 500 for deep reasoning
            temperature: 0.7,
            contextWindow: 8192 // Full reasoning context
        });
    }
}
