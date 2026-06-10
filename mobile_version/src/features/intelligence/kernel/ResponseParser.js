/**
 * JAOS Phase 1: Response Parser
 * Responsibility: Extracting and cleaning the final assistant response.
 * Prevents prompt leakage and recursive artifacts.
 */

export class ResponseParser {
    static distill(raw) {
        if (!raw || typeof raw !== 'string') return "";
        
        let distilled = raw;

        // 1. SPLIT & POP (Jump past prompt echoes)
        const roleMarkers = [
            /\nassistant[:\s]+/i, 
            /^assistant[:\s]+/i, 
            /<\|im_start\|>assistant\n/i,
            /### Assistant:\s*/i
        ];

        for (const marker of roleMarkers) {
            const parts = distilled.split(marker);
            if (parts.length > 1) {
                distilled = parts.pop();
            }
        }

        // 2. TAG PURGE (Cognitive Firewall)
        const purgePatterns = [
            /<TONE_CONTEXT>[\s\S]*?<\/TONE_CONTEXT>/gi,
            /<COGNITIVE_PROCESSING>[\s\S]*?<\/COGNITIVE_PROCESSING>/gi,
            /<MEMORY_ACCESS>[\s\S]*?<\/MEMORY_ACCESS>/gi,
            /<INTERNAL_MONOLOGUE>[\s\S]*?<\/INTERNAL_MONOLOGUE>/gi,
            /<SYSTEM_KERNEL>[\s\S]*?<\/SYSTEM_KERNEL>/gi,
            /<MEMORY_STREAM>[\s\S]*?<\/MEMORY_STREAM>/gi,
            /\[MEMORY\]:[\s\S]*?\n\n/gi,
            /\[INPUT\]:[\s\S]*/gi,
            /^(assistant|user|system|jarvis)[:\s\n]*/gim,
            /\n(assistant|user|system|jarvis)[:\s\n]*/gim,
        ];

        for (const pattern of purgePatterns) {
            distilled = distilled.replace(pattern, '');
        }

        // 3. SCALE CONTROL (Proportionality)
        distilled = distilled.trim();
        
        return distilled;
    }
}
