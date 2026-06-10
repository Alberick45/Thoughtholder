/**
 * JAOS Phase 6: Self-Evaluation Module
 * Evaluates the performance and accuracy of recent interactions.
 */

export const evaluateLastInteraction = (userResponse, aiAction) => {
    const criticalKeywords = ['wrong', 'incorrect', 'bad', 'no', 'stop', 'not what I meant'];
    const positiveKeywords = ['thanks', 'great', 'yes', 'exactly', 'perfect'];
    
    let scoreDelta = 0;
    const content = userResponse.toLowerCase();
    
    if (criticalKeywords.some(k => content.includes(k))) scoreDelta = -0.2;
    if (positiveKeywords.some(k => content.includes(k))) scoreDelta = 0.1;
    
    return {
        correctionRequired: scoreDelta < 0,
        performanceDelta: scoreDelta
    };
};
