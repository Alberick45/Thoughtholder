/**
 * JAOS Phase 3: Urgency Classifier
 * Detects time-criticality, emergency signals, and system risks.
 */

export const classifyUrgency = (thought) => {
    let score = 0.1; // Base urgency

    const content = thought.content.toLowerCase();
    
    // Time-based triggers
    if (content.includes('deadline') || content.includes('due') || content.includes('today')) score += 0.4;
    if (content.includes('asap') || content.includes('urgent') || content.includes('critical')) score += 0.5;
    
    // Event proximity (handled by daysLeft logic elsewhere, but integrated here)
    const daysLeftMatch = thought.content.match(/in (\d+) days/);
    if (daysLeftMatch) {
        const days = parseInt(daysLeftMatch[1]);
        if (days === 0) score += 0.8;
        if (days === 1) score += 0.5;
    }

    return Math.min(1.0, score);
};
