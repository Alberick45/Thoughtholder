/**
 * JAOS Phase 3: Relevance Scorer
 * Scores incoming stimuli against the current Working Memory and Active Focus.
 */

export const calculateRelevance = (stimulus, workingMemory) => {
    if (!stimulus || !workingMemory) return 0;

    const content = stimulus.content.toLowerCase();
    const focusItems = workingMemory.activeFocus || [];
    
    // Simple keyword overlap for now (semantic similarity in Phase 4)
    let score = 0;
    focusItems.forEach(item => {
        const itemWords = item.content.toLowerCase().split(' ');
        itemWords.forEach(word => {
            if (word.length > 3 && content.includes(word)) score += 0.1;
        });
    });

    return Math.min(1.0, score);
};
