/**
 * JAOS Phase 5: Action Confidence Scorer
 * Evaluates the reliability and certainty of a proposed autonomous action.
 */

export const calculateConfidence = (action, evidenceCount, semanticRelevance) => {
    // 1. Evidence Quantity (Max 0.4)
    const quantityScore = Math.min(0.4, evidenceCount * 0.1);
    
    // 2. Semantic Alignment (Max 0.4)
    const alignmentScore = Math.min(0.4, semanticRelevance);
    
    // 3. Complexity Penalty (More complex actions require more certainty)
    const complexityPenalty = action.type === 'system_change' ? 0.2 : 0;
    
    // 4. Historical Success (Placeholder for Phase 8)
    const historyScore = 0.2; 

    const total = quantityScore + alignmentScore + historyScore - complexityPenalty;
    return Math.max(0, Math.min(1.0, total));
};
