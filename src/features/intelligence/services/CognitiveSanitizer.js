/**
 * JAOS Phase 1 & 2: Cognitive Sanitizer
 * Responsibility: Extracting ONLY the final assistant response.
 * Filters out: System prompts, memory streams, recursive tags, and chain-of-thought.
 */

export class CognitiveSanitizer {
    /**
     * Distills a raw AI response into a clean, human-readable message.
     */
    static distill(raw) {
        if (!raw || typeof raw !== 'string') return "";
        
        let distilled = raw;

        // 1. ROLE-BASED SEGMENTATION (Find the last transition)
        const roleMarkers = [
            /\nassistant[:\s]+/i, 
            /\nuser[:\s]+/i, 
            /\nsystem[:\s]+/i, 
            /^assistant[:\s]+/i, 
            /^user[:\s]+/i, 
            /^system[:\s]+/i,
            /\[INPUT\][:\s]+/i,
            /\[MEMORY\][:\s]+/i,
            /<\|im_start\|>assistant\n/i,
            /### Assistant:\s*/i
        ];

        for (const marker of roleMarkers) {
            const parts = distilled.split(marker);
            if (parts.length > 1) {
                // We assume the model appended the new response at the end
                distilled = parts.pop();
            }
        }

        // 2. TAG-BASED PURGE (Remove all internal cognitive markers)
        const purgePatterns = [
            // Structural Tags
            /<TONE_CONTEXT>[\s\S]*?<\/TONE_CONTEXT>/gi,
            /<COGNITIVE_PROCESSING>[\s\S]*?<\/COGNITIVE_PROCESSING>/gi,
            /<MEMORY_ACCESS>[\s\S]*?<\/MEMORY_ACCESS>/gi,
            /<SUBJECTIVE_ASSESSMENT>[\s\S]*?<\/SUBJECTIVE_ASSESSMENT>/gi,
            /<CONVERSATIONAL_STRATEGY>[\s\S]*?<\/CONVERSATIONAL_STRATEGY>/gi,
            /<RESPONSE_PRESENTATION>[\s\S]*?<\/RESPONSE_PRESENTATION>/gi,
            /<INTERNAL_MONOLOGUE>[\s\S]*?<\/INTERNAL_MONOLOGUE>/gi,
            /<SYSTEM_KERNEL>[\s\S]*?<\/SYSTEM_KERNEL>/gi,
            /<DISPLAY_PRESENTATION>[\s\S]*?<\/DISPLAY_PRESENTATION>/gi,
            /<COGNITIVE_OVERSIGHT>[\s\S]*?<\/COGNITIVE_OVERSIGHT>/gi,
            /<MEMORY_STREAM>[\s\S]*?<\/MEMORY_STREAM>/gi,
            /<CURRENT_INPUT>[\s\S]*?<\/CURRENT_INPUT>/gi,
            /<\|im_start\|>[\s\S]*?<\|im_end\|>/gi,
            
            // Text-based Headers
            /\[MEMORY\]:[\s\S]*?\n\n/gi,
            /\[INPUT\]:[\s\S]*/gi,
            /\[RESPONSE_PROTOCOL\]:[\s\S]*?\d+\..*?\n/gi,
            /\[INTERNAL MONOLOGUE[\s\S]*?\]/gi,
            /\[JAOS_UPDATE:.*?\]/gi,
            /\[COGNITIVE LEASH[\s\S]*?\]/gi,

            // Raw Metadata leaks
            /^(assistant|user|system|jarvis)[:\s\n]*/gim,
            /\n(assistant|user|system|jarvis)[:\s\n]*/gim,
        ];

        for (const pattern of purgePatterns) {
            distilled = distilled.replace(pattern, '');
        }

        // 3. CLEANUP (Trim and normalize)
        distilled = distilled
            .replace(/\s+/g, ' ') // Collapse whitespace
            .replace(/assistant/gi, '') // Final catch-all for the word 'assistant' if it leaked as text
            .trim();

        return distilled;
    }

    /**
     * Checks if the output is malformed or purely system-echoed.
     */
    static isMalformed(text) {
        if (!text || text.length < 2) return true;
        // If the text contains too many structural markers, it's likely a leaked prompt
        const leakMarkers = ['<MEMORY_STREAM>', 'CORE RULES:', 'PRIORITY ORDER:'];
        return leakMarkers.some(m => text.includes(m));
    }
}
