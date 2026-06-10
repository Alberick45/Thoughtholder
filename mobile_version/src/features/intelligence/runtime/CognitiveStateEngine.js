/**
 * LAYER 3 — COGNITIVE STATE ENGINE
 * Responsibility: Construct derived environmental reality.
 * 
 * This layer overrides raw memory with structured cognition.
 * It handles noise suppression, recency weighting, and relevance ranking.
 */

export class CognitiveStateEngine {
    /**
     * Builds the global cognitive state from analyzed thoughts.
     */
    static construct(analyzedThoughts, awareness = {}, lifeModel = {}) {
        const now = Date.now();
        const oneDay = 24 * 60 * 60 * 1000;

        const state = {
            pending_tasks: [],
            active_projects: [],
            buy_list: [],
            unresolved_threads: [],
            recurring_interests: [],
            urgency_map: {},
            last_updated: now
        };

        // 1. Process Tasks & Projects
        analyzedThoughts.forEach(thought => {
            const age = now - thought.created_at;
            const weight = Math.max(0.1, 1 - (age / (oneDay * 7))); // Decays over 7 days

            if (thought.type === 'TASK') {
                state.pending_tasks.push({ val: thought.value, weight });
            } else if (thought.type === 'PROJECT') {
                state.active_projects.push({ val: thought.value, weight });
            } else if (thought.type === 'BUY_ITEM') {
                state.buy_list.push({ val: thought.value, weight });
            }
        });

        // 2. Rank by Weight (Recency)
        state.pending_tasks.sort((a, b) => b.weight - a.weight);
        state.buy_list.sort((a, b) => b.weight - a.weight);

        // 3. Noise Suppression: Limit lists
        state.pending_tasks = state.pending_tasks.slice(0, 15);
        state.buy_list = state.buy_list.slice(0, 10);

        // 4. Urgency Mapping
        state.urgency_map = {
            task_pressure: state.pending_tasks.length / 15,
            procurement_pressure: state.buy_list.length / 10,
            intent_drift: awareness.drift || 0
        };

        return state;
    }
}
