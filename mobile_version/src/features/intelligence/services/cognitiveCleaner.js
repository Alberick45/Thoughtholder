/**
 * JAOS Cognitive Cleaner
 * Safely wipes old cognitive state, conversation history, and psychological profiles.
 */

import { db } from '../../../shared/infrastructure/db';

export const clearCognitiveMemory = async () => {
    try {
        // 1. Clear Conversation History (Jarvis Logs)
        const logs = await db.thoughts.filter(t => t.type === 'jarvis_log').toArray();
        await db.thoughts.bulkDelete(logs.map(l => l.id));

        // 2. Clear Psychological Profile
        await db.settings.delete('jarvis_profile');
        await db.settings.delete('jaos_identity');

        // 3. Clear LocalStorage Cognitive Flags
        localStorage.removeItem('jaos_momentum_score');
        localStorage.removeItem('jaos_state_history');
        localStorage.removeItem('jaos_fatigue_level');
        localStorage.removeItem('jaos_current_state');
        localStorage.removeItem('jaos_forecast');
        localStorage.removeItem('jaos_habits');
        localStorage.removeItem('jaos_evolution_state');

        console.log("[COGNITIVE_CLEANER] Memory wipe complete. JAOS is now in a clean state.");
        return true;
    } catch (error) {
        console.error("[COGNITIVE_CLEANER] Wipe failed:", error);
        return false;
    }
};
