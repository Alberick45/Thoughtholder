/**
 * JAOS Environmental Signal Aggregator
 * 
 * Periodically scans the thought database to extract high-level 
 * behavioral and environmental signals.
 */

export class EnvironmentalSignalAggregator {
    constructor(db) {
        this.db = db;
    }

    /**
     * Scans for signals across all cognitive layers
     */
    async aggregate() {
        const thoughts = await this.db.thoughts.toArray();
        const now = Date.now();
        const oneDay = 24 * 60 * 60 * 1000;
        const fourHours = 4 * 60 * 60 * 1000;

        // 1. Task Momentum (Completion Rate)
        const recentTasks = thoughts.filter(t => t.type === 'task' && (now - t.created_at) < oneDay);
        const completedRecent = recentTasks.filter(t => t.status === 'archived').length;
        const totalRecent = recentTasks.length;
        const momentum = totalRecent > 0 ? completedRecent / totalRecent : 0;

        // 2. Intent Drift (Stale Fresh Items)
        // High drift = many fresh items not being moved to active or archived
        const staleFresh = thoughts.filter(t => t.status === 'fresh' && (now - t.created_at) > (oneDay * 2)).length;
        const drift = staleFresh > 5 ? Math.min(1.0, staleFresh / 20) : 0;

        // 3. Cognitive Density (Volume of input)
        const recentInput = thoughts.filter(t => (now - t.created_at) < fourHours).length;
        const density = Math.min(1.0, recentInput / 15); // >15 inputs in 4h is high density

        // 4. Procurement Pressure (Unfinished buys)
        const pendingBuys = thoughts.filter(t => t.type === 'buy' && t.status !== 'archived').length;
        const pressure = Math.min(1.0, pendingBuys / 10);

        return {
            timestamp: now,
            momentum,    // 0.0 to 1.0
            drift,       // 0.0 to 1.0
            density,     // 0.0 to 1.0
            pressure,    // 0.0 to 1.0
            signals: {
                taskCount: totalRecent,
                staleCount: staleFresh,
                inputCount: recentInput,
                buyCount: pendingBuys
            }
        };
    }

    /**
     * Saves the aggregated state to persistent storage
     */
    async persist() {
        const state = await this.aggregate();
        localStorage.setItem('jaos_awareness_state', JSON.stringify(state));
        
        try {
            await this.db.settings.put({ key: 'jaos_awareness_state', value: state });
        } catch (e) {
            console.warn("[AWARENESS] DB persistence failed:", e);
        }

        console.log("[AWARENESS] Signal aggregation complete. Momentum:", state.momentum.toFixed(2));
        return state;
    }
}
