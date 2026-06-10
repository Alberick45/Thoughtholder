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
        if (!rawResponse) return "I'm processing the current environment, but have no specific update yet.";
        
        // If in debug mode, allow raw output
        if (debugMode) return rawResponse;

        let refined = rawResponse;

        // 1. Strip machine narration and diagnostic labels
        refined = refined.replace(/\[ENVIRONMENT_SNAPSHOT\]/gi, '');
        refined = refined.replace(/\[JAOS_UPDATE:.*?\]/gi, '');
        refined = refined.replace(/\[JAOS_ACTION:.*?\]/gi, ''); // Strip actions from visible text
        refined = refined.replace(/Tasks: None found/gi, 'You’re actually relatively clear right now.');
        refined = refined.replace(/Environment snapshot validated\./gi, 'Everything seems aligned.');
        refined = refined.replace(/Memory scan complete\./gi, '');
        refined = refined.replace(/appLevel: \d+/gi, '');

        // 2. Prevent Object Leakage Catch-all
        refined = refined.replace(/\[object Object\]/g, '[System Detail]');

        // 3. Fallback for empty results after stripping
        const finalContent = refined.trim();
        if (finalContent.length < 2) {
            return "Just checking in—the environment seems stable for now.";
        }

        return finalContent;
    }
}
