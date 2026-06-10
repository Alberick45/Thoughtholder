/**
 * JAOS Phase 2: Memory Decay Module
 * Manages the aging of information, importance scoring, and eventual data cleanup.
 */

import { db } from '../../../shared/infrastructure/db';

export const applyDecay = async () => {
    try {
        const now = Date.now();
        const allThoughts = await db.thoughts.toArray();
        
        for (const t of allThoughts) {
            if (t.status === 'fresh' || t.status === 'active') {
                const ageDays = (now - t.created_at) / (1000 * 60 * 60 * 24);
                // Ephemeral thoughts decay faster
                const isEphemeral = t.tags?.includes('net-result') || t.tags?.includes('siphoned');
                const decayRate = isEphemeral ? 0.5 : 0.05; // Importance drops per day
                
                const newScore = Math.max(0, (t.importance_score || 0.5) - (ageDays * decayRate));
                
                if (newScore < 0.1 && t.status === 'fresh') {
                    await db.thoughts.update(t.id, { status: 'ignored', importance_score: newScore });
                } else {
                    await db.thoughts.update(t.id, { importance_score: newScore });
                }
            }
        }
        console.log("[MEMORY_DECAY] Applied systemic decay to active nodes.");
    } catch (error) {
        console.error("[MEMORY_DECAY] Execution error:", error);
    }
};
