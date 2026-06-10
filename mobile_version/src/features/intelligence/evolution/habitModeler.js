/**
 * JAOS Phase 8: Habit Modeler
 * Identifies and persists recurring user behavior patterns and energy cycles.
 */

import { db } from '../../../shared/infrastructure/db';

export const analyzeHabits = async () => {
    try {
        const logs = await db.thoughts.filter(t => t.type === 'jarvis_log').toArray();
        
        // Simple hour-of-day distribution
        const distribution = logs.reduce((acc, log) => {
            const hour = new Date(log.created_at).getHours();
            acc[hour] = (acc[hour] || 0) + 1;
            return acc;
        }, {});
        
        const peakHour = Object.entries(distribution).sort((a,b) => b[1] - a[1])[0]?.[0];

        return {
            peakActivityHour: peakHour,
            energyPattern: peakHour > 18 ? 'Night Owl' : 'Early Bird'
        };
    } catch (error) {
        console.error("[HABIT_MODELER] Habit analysis failed:", error);
        return null;
    }
};
