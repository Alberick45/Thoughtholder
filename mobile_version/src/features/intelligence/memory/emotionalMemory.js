/**
 * JAOS Phase 2: Emotional Memory Module
 * Tracks user mood, recurring frustrations, and emotional tone.
 */

import { db } from '../../../shared/infrastructure/db';

export const getEmotionalProfile = async () => {
    try {
        const psychProfile = await db.settings.get('jarvis_profile');
        const recentEmotionalLogs = await db.thoughts
            .filter(t => t.type === 'jarvis_log' && t.emotional_tone)
            .reverse()
            .limit(10)
            .toArray();
            
        return {
            longTermProfile: psychProfile?.value || 'Neutral/Stable',
            recentTrend: recentEmotionalLogs.map(l => l.emotional_tone)
        };
    } catch (error) {
        console.error("[EMOTIONAL_MEMORY] Retrieval error:", error);
        return { longTermProfile: 'Neutral', recentTrend: [] };
    }
};

export const detectFrustration = (content) => {
    const frustrationTriggers = ['annoying', 'stupid', 'broken', 'hate', 'frustrated', 'why doesn\'t', 'argh'];
    return frustrationTriggers.some(trigger => content.toLowerCase().includes(trigger));
};
