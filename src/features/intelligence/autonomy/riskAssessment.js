/**
 * JAOS Phase 5: Risk Assessment Module
 * Evaluates the potential "Blast Radius" and irreversibility of an action.
 */

export const assessRisk = (action) => {
    const riskLevels = {
        'net_search': 0.1,    // Low risk, read-only
        'memory_add': 0.2,   // Low risk, additive
        'task_complete': 0.4, // Moderate risk, state change
        'data_delete': 0.9,   // High risk, destructive
        'system_config': 0.8  // High risk, structural
    };

    const baseRisk = riskLevels[action.type] || 0.5;
    
    return {
        score: baseRisk,
        isHighRisk: baseRisk > 0.7,
        requiresConfirmation: baseRisk > 0.6
    };
};
