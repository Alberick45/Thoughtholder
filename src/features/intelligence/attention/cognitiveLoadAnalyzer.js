/**
 * JAOS Phase 3: Cognitive Load Analyzer
 * Estimates current user workload and focus density.
 */

export const analyzeCognitiveLoad = (recentThoughts, activeTasks) => {
    // 1. Task Density
    const taskLoad = activeTasks.length * 0.2; // Each active task adds 20% load
    
    // 2. Interaction Frequency
    const now = Date.now();
    const recentActivity = recentThoughts.filter(t => (now - t.created_at) < (15 * 60 * 1000)); // Last 15 mins
    const interactionLoad = recentActivity.length * 0.1;
    
    // 3. System Pressure (e.g. lots of stale thoughts)
    const pressureLoad = recentThoughts.filter(t => t.stale_score > 5).length * 0.05;

    return Math.min(1.0, taskLoad + interactionLoad + pressureLoad);
};
