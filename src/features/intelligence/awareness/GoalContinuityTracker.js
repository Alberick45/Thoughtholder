/**
 * JAOS Goal Continuity Tracker
 * 
 * Tracks unfinished intentions and project momentum over time.
 * Detects when a project has stalled or when a high-priority 
 * goal is being drifted from.
 */

export class GoalContinuityTracker {
    constructor(db) {
        this.db = db;
    }

    /**
     * Identifies stalled projects based on life model pillars
     */
    async analyzeContinuity(lifeModel, awareness) {
        const thoughts = await this.db.thoughts.toArray();
        const now = Date.now();
        const twoDays = 2 * 24 * 60 * 60 * 1000;
        const threeDays = 3 * 24 * 60 * 60 * 1000;

        const results = {
            stalledPillars: [],
            driftedTasks: [],
            momentumStatus: awareness.momentum > 0.6 ? 'Healthy' : 'Stalled'
        };

        // 1. Check for stalled pillars
        if (lifeModel.pillars) {
            for (const pillar of lifeModel.pillars) {
                const pillarThoughts = thoughts.filter(t => 
                    t.content.toLowerCase().includes(pillar.toLowerCase())
                );
                
                const lastActivity = Math.max(...pillarThoughts.map(t => t.created_at), 0);
                
                if (lastActivity > 0 && (now - lastActivity) > threeDays) {
                    results.stalledPillars.push({
                        name: pillar,
                        daysIdle: Math.floor((now - lastActivity) / (24 * 60 * 60 * 1000))
                    });
                }
            }
        }

        // 2. Detect "Drifted Tasks" 
        // Tasks that were created recently but have high stale scores or were ignored
        const pendingTasks = thoughts.filter(t => 
            t.type === 'task' && t.status !== 'archived' && t.status !== 'trash'
        );

        results.driftedTasks = pendingTasks
            .filter(t => t.stale_score > 4 || (now - t.created_at) > (twoDays))
            .map(t => t.content.substring(0, 50))
            .slice(0, 3);

        localStorage.setItem('jaos_continuity_state', JSON.stringify(results));
        return results;
    }

    static getContinuity() {
        return JSON.parse(localStorage.getItem('jaos_continuity_state') || '{}');
    }
}
