/**
 * JAOS Phase 3: Silence Evaluator
 * Evaluates the quality of silence vs. the quality of speech.
 */

export const evaluateSilence = (netBenefit, confidence) => {
    // If the benefit is marginal and confidence is low, silence is better
    if (netBenefit < 0.2 && confidence < 0.6) {
        return {
            action: 'SILENCE',
            reason: 'Low confidence marginal benefit'
        };
    }
    
    // If confidence is very low, silence is mandatory to preserve trust
    if (confidence < 0.3) {
        return {
            action: 'SILENCE',
            reason: 'Insufficient confidence for interruption'
        };
    }

    return { action: 'PROCEED' };
};
