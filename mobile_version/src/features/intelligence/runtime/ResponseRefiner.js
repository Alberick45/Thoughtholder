/**
 * LAYER 6 & 7 — ABSTRACTION & COMPRESSION ENGINE
 * Responsibility: Separate internal cognition from user-visible conversation.
 * 
 * This engine transforms structured cognition into natural conversational minimalism.
 * It prevents machine narration and architecture leakage.
 */

export class ResponseRefiner {
    /**
     * Refines the AI's raw response based on the "Grounded Operating System" philosophy.
     */
    static refine(rawResponse, snapshot, debugMode = false) {
        // If in debug mode, allow raw output
        if (debugMode) return rawResponse;

        let refined = rawResponse;

        // 1. Strip machine narration and diagnostic labels
        refined = refined.replace(/\[ENVIRONMENT_SNAPSHOT\]/g, '');
        refined = refined.replace(/\[JAOS_UPDATE:.*?\]/g, '');
        refined = refined.replace(/Tasks: None found/gi, 'You’re actually relatively clear right now.');
        refined = refined.replace(/Environment snapshot validated\./gi, 'Everything seems aligned.');
        refined = refined.replace(/Memory scan complete\./gi, '');
        refined = refined.replace(/appLevel: \d+/gi, '');

        // 2. Compression Logic: The more confident the retrieval, the shorter the response.
        // (Heuristic: If the response contains specific items from the snapshot, it is confident)
        const hasSpecifics = snapshot.includes('TASKS:') && !snapshot.includes('None found');
        
        if (hasSpecifics && refined.length > 200) {
            // Suggest trimming or summarizing if it's too verbose for a confident state
            // (In a real implementation, this might be a second LLM pass or a clever regex)
        }

        // 3. Prevent Object Leakage Catch-all
        refined = refined.replace(/\[object Object\]/g, '[System Detail]');

        return refined.trim();
    }
}
