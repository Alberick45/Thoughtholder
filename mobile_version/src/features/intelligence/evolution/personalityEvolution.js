/**
 * JAOS Phase 8: Advanced Relational Evolution System
 * Implements a multi-axis scoring model for emergent relationship depth.
 */

import { db } from '../../../shared/infrastructure/db';

export const calculateEvolutionState = async () => {
    try {
        const idStore = await db.settings.get('jaos_identity');
        const identity = idStore ? (typeof idStore.value === 'string' ? JSON.parse(idStore.value) : idStore.value) : null;
        
        // 1. Identity Certainty Axis (0.0 to 1.0)
        const hasName = identity?.user_name && identity.user_name !== 'User';
        const hasPrefs = identity?.preferences && identity.preferences.length > 20;
        const identityConfidence = (hasName ? 0.7 : 0) + (hasPrefs ? 0.3 : 0);

        // 2. Interaction Quality & Volume Axis
        const logs = await db.thoughts.filter(t => t.type === 'jarvis_log').toArray();
        const convoCount = logs.length;
        
        // Interaction Quality Calculation (Simple heuristic: length and complexity of logs)
        const interactionQuality = Math.min(1.0, logs.reduce((acc, log) => {
            const weight = log.content.length > 500 ? 1.0 : (log.content.length > 100 ? 0.5 : 0.1);
            return acc + weight;
        }, 0) / 50);

        // 3. Shared History Axis
        // 3. Shared History Axis
        let birthDate;
        try {
            const birthStore = await db.settings.get('jaos_birth_date');
            if (birthStore) {
                birthDate = birthStore.value;
            } else {
                birthDate = parseInt(localStorage.getItem('jaos_birth_date')) || Date.now();
                await db.settings.put({ key: 'jaos_birth_date', value: birthDate });
                localStorage.setItem('jaos_birth_date', birthDate);
            }
        } catch (e) {
            birthDate = parseInt(localStorage.getItem('jaos_birth_date')) || Date.now();
        }
        
        const durationMs = Date.now() - birthDate;
        const durationDays = durationMs / (1000 * 60 * 60 * 24);
        const sharedHistoryScore = Math.min(1.0, durationDays / 30);

        // 4. Memory Continuity Axis
        const allThoughts = await db.thoughts.toArray();
        const linkedCount = allThoughts.filter(t => t.linked_thoughts?.length > 0).length;
        const memoryContinuity = Math.min(1.0, linkedCount / (allThoughts.length || 1));

        // 5. Relationship Decay (30 days inactivity penalty)
        const lastInteraction = logs.length > 0 ? logs[logs.length - 1].created_at : birthDate;
        const inactiveDays = (Date.now() - lastInteraction) / (1000 * 60 * 60 * 24);
        let decayFactor = 1.0;
        if (inactiveDays > 30) {
            decayFactor = 0.9 ** (Math.floor(inactiveDays / 30));
        }

        // --- GLOBAL RELATIONAL SCORE (Weighted Model) ---
        const relationalScore = (
            (interactionQuality * 0.30) +
            (memoryContinuity * 0.20) +
            (identityConfidence * 0.20) +
            (sharedHistoryScore * 0.30)
        ) * decayFactor;

        // --- PHASE DETERMINATION ---
        let depth = 'STRANGER';
        if (relationalScore > 0.15 && identityConfidence >= 0.4 && convoCount > 10) depth = 'ACQUAINTANCE';
        if (relationalScore > 0.45 && identityConfidence >= 0.7 && durationDays > 7 && convoCount > 50) depth = 'COMPANION';
        if (relationalScore > 0.75 && identityConfidence >= 0.9 && durationDays > 30 && convoCount > 200) depth = 'PEER_ORCHESTRATOR';

        return {
            depth,
            relationalScore: relationalScore.toFixed(4),
            axes: {
                identityConfidence,
                interactionQuality: interactionQuality.toFixed(2),
                sharedHistoryScore: sharedHistoryScore.toFixed(2),
                memoryContinuity: memoryContinuity.toFixed(2),
                decayFactor: decayFactor.toFixed(2)
            },
            stats: {
                convoCount,
                durationDays: Math.floor(durationDays),
                inactiveDays: Math.floor(inactiveDays)
            }
        };
    } catch (error) {
        console.error("[EVOLUTION] Calculation failed:", error);
        return { depth: 'STRANGER', relationalScore: 0 };
    }
};
