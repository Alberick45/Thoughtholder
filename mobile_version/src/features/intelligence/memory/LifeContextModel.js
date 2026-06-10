/**
 * JAOS Life Context Model
 * 
 * Maintains a persistent, probabilistic understanding of the user's 
 * ongoing life structure, focuses, and patterns.
 */

export class LifeContextModel {
    constructor(db) {
        this.db = db;
    }

    /**
     * Updates the model based on current environmental signals and recent data
     */
    async update() {
        const thoughts = await this.db.thoughts.toArray();
        const awareness = JSON.parse(localStorage.getItem('jaos_awareness_state') || '{}');
        const now = Date.now();
        const twoDays = 2 * 24 * 60 * 60 * 1000;

        // 1. Resolve Active Focus (Highest keyword density in last 48h)
        const recent = thoughts.filter(t => (now - t.created_at) < twoDays);
        const keywords = this.extractKeywords(recent);
        const topFocus = Object.entries(keywords).sort((a, b) => b[1] - a[1])[0]?.[0] || 'Unknown';

        // 2. Resolve Long-term Pillars (Recurring keywords over last 14 days)
        const longTerm = thoughts.filter(t => (now - t.created_at) < (14 * 24 * 60 * 60 * 1000));
        const ltKeywords = this.extractKeywords(longTerm);
        const pillars = Object.entries(ltKeywords)
            .filter(([word, count]) => count > 5) // Occurs at least 5 times in 14 days
            .map(([word]) => word)
            .slice(0, 5);

        // 3. Behavioral State Estimation
        const state = {
            focus: topFocus,
            pillars: pillars,
            momentum: awareness.momentum || 0,
            drift: awareness.drift || 0,
            density: awareness.density || 0,
            updated_at: now
        };

        localStorage.setItem('jaos_life_model', JSON.stringify(state));
        
        try {
            await this.db.settings.put({ key: 'jaos_life_model', value: state });
        } catch (e) {
            console.warn("[LIFE_MODEL] DB persistence failed:", e);
        }

        return state;
    }

    extractKeywords(thoughts) {
        const counts = {};
        const stopWords = new Set(['the', 'a', 'an', 'and', 'or', 'to', 'for', 'of', 'in', 'on', 'with', 'about', 'is', 'it', 'this', 'that', 'i', 'my', 'your', 'be', 'are']);
        
        thoughts.forEach(t => {
            const content = (t.content || '').toLowerCase();
            const words = content.replace(/[^\w\s]/g, '').split(/\s+/);
            words.forEach(w => {
                if (w.length > 3 && !stopWords.has(w)) {
                    counts[w] = (counts[w] || 0) + 1;
                }
            });
        });
        return counts;
    }

    /**
     * Returns the current model state
     */
    static getModel() {
        return JSON.parse(localStorage.getItem('jaos_life_model') || '{}');
    }
}
