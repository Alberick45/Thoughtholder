/**
 * JAOS Phase 5: Execution Policy
 * Enforces the strict Confidence Bands and Action Safety rules.
 */

export const getExecutionPolicy = (confidence, risk) => {
    // Phase 5 Confidence Bands
    if (confidence < 0.4 || risk.isHighRisk) {
        return {
            mode: 'CONSULTATIVE',
            instruction: 'Ask clarifying questions. DO NOT act.',
            allowExecution: false
        };
    }

    if (confidence < 0.7) {
        return {
            mode: 'SUGGESTIVE',
            instruction: 'Suggest the action cautiously. Wait for user approval.',
            allowExecution: false
        };
    }

    if (confidence < 0.85) {
        return {
            mode: 'SEMI_AUTONOMOUS',
            instruction: 'Proceed with low-risk execution, but notify user immediately.',
            allowExecution: true
        };
    }

    return {
        mode: 'AUTONOMOUS',
        instruction: 'Full execution allowed. Silently fulfill the intent.',
        allowExecution: true
    };
};
