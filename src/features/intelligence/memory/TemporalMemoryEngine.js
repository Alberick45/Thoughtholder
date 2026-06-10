/**
 * JAOS Temporal Memory Engine
 * 
 * Tracks behavioral rhythms, peak energy windows, and 
 * daily activity patterns over time.
 */

export class TemporalMemoryEngine {
    constructor(db) {
        this.db = db;
    }

    /**
     * Analyzes activity logs to identify the user's daily rhythm
     */
    async analyzeRhythms() {
        const thoughts = await this.db.thoughts.toArray();
        const now = Date.now();
        const thirtyDays = 30 * 24 * 60 * 60 * 1000;

        // 1. Group activity by hour of day
        const hourlyActivity = Array(24).fill(0);
        const recent = thoughts.filter(t => (now - t.created_at) < thirtyDays);

        recent.forEach(t => {
            const date = new Date(t.created_at);
            const hour = date.getHours();
            hourlyActivity[hour]++;
        });

        // 2. Identify Peak Productivity Window
        let peakHour = 0;
        let maxActivity = 0;
        for (let h = 0; h < 24; h++) {
            if (hourlyActivity[h] > maxActivity) {
                maxActivity = hourlyActivity[h];
                peakHour = h;
            }
        }

        // 3. Estimate Current Energy Phase
        const currentHour = new Date().getHours();
        const relativeActivity = hourlyActivity[currentHour] / (maxActivity || 1);
        let energyPhase = 'Low';
        if (relativeActivity > 0.8) energyPhase = 'Peak';
        else if (relativeActivity > 0.4) energyPhase = 'Moderate';

        const rhythmState = {
            peakHour,
            hourlyActivity,
            energyPhase,
            updated_at: now
        };

        localStorage.setItem('jaos_temporal_rhythm', JSON.stringify(rhythmState));
        try {
            await this.db.settings.put({ key: 'jaos_temporal_rhythm', value: rhythmState });
        } catch (e) {
            console.warn("[TEMPORAL] DB persistence failed:", e);
        }
        return rhythmState;
    }

    static getRhythm() {
        return JSON.parse(localStorage.getItem('jaos_temporal_rhythm') || '{}');
    }
}
