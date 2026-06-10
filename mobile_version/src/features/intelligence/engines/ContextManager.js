/**
 * JAOS Context Manager
 * Handles prompt caching, context compression, and adaptive token limits.
 * Essential for keeping local AI execution fast and responsive.
 */

import { db } from '../../../shared/infrastructure/db';

export class ContextManager {
    constructor() {
        this.cache = new Map();
        this.MAX_CONTEXT_TOKENS = 4000; // Hard limit for local execution speed
    }

    /**
     * Lazy Context Loading
     * Only retrieves the specific memory layers required by the current Cognitive State.
     */
    async getAdaptiveContext(query, stateConfig) {
        const safeQuery = String(query || '');
        const cacheKey = `ctx_${safeQuery.substring(0, 20)}`;
        if (this.cache.has(cacheKey)) {
            console.log("[CONTEXT_MANAGER] Cache hit for query.");
            return this.cache.get(cacheKey);
        }

        let context = { working: [], semantic: [], episodic: [] };

        // 1. Working Memory (Always load, but compress)
        const recent = await db.thoughts.orderBy('created_at').reverse().limit(10).toArray();
        context.working = this.compressText(recent.map(t => t.content).join('\n'));

        // 2. Semantic/Episodic (Lazy Load based on State Intensity)
        if (stateConfig.intensity === 'High' || stateConfig.intensity === 'Max') {
            // Expensive vector retrieval ONLY for Deep Focus or Reactive
            const { getCognitiveContext } = await import('../memory/memoryRetriever');
            const fullMem = await getCognitiveContext(query);
            
            // Context Compression: Summarize or clip older memories
            context.semantic = this.compressArray(fullMem.semantic || [], 5);
            context.episodic = this.compressArray(fullMem.episodic || [], 3);
        }

        this.cache.set(cacheKey, context);
        setTimeout(() => this.cache.delete(cacheKey), 60000); // 1 min TTL

        return context;
    }

    /**
     * Context Compression Engine
     * Strips filler words and limits token length to avoid model overload.
     */
    compressText(text, maxChars = 2000) {
        if (!text) return '';
        const safeText = String(text);
        let compressed = safeText.substring(0, maxChars);
        // Simple heuristic compression: remove excess whitespace and non-critical stop words
        compressed = compressed.replace(/\s+/g, ' ')
                               .replace(/\b(the|a|an|is|are|was|were)\b/gi, '')
                               .trim();
        return compressed;
    }

    compressArray(arr, maxItems) {
        if (!arr || arr.length === 0) return [];
        return arr.slice(0, maxItems).map(item => ({
            ...item,
            content: this.compressText(item.content, 500) // Cap individual items
        }));
    }
}

export const contextManager = new ContextManager();
