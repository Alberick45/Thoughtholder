/**
 * JAOS Phase 2: Context Compressor Module
 * Compresses historical context into high-density summaries and momentum snapshots.
 */

import { askJarvis } from '../services/jarvis';

export const compressContext = async (thoughts) => {
    if (thoughts.length < 5) return null;
    
    const textToSummarize = thoughts.map(t => t.content).join('\n---\n');
    const prompt = `Compress the following sequence of user thoughts and interactions into a single, high-density paragraph describing the current "Momentum". What is the user trying to achieve right now? What are the recurring themes? Be clinical and precise.`;
    
    try {
        const summary = await askJarvis(textToSummarize, prompt);
        return summary;
    } catch (error) {
        console.error("[CONTEXT_COMPRESSOR] Compression failed:", error);
        return null;
    }
};

export const getMomentumSnapshot = (recentThoughts) => {
    const categories = recentThoughts.reduce((acc, t) => {
        acc[t.type] = (acc[t.type] || 0) + 1;
        return acc;
    }, {});
    
    return `Momentum: ${Object.entries(categories).map(([k, v]) => `${v} ${k}s`).join(', ')}`;
};
