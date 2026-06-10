/**
 * JAOS Phase 6: Emotional Reasoner
 * Infers deep emotional state and recurring frustration patterns.
 */

import { getEmotionalProfile } from '../memory/emotionalMemory';

export const inferMoodState = async () => {
    const profile = await getEmotionalProfile();
    const trend = profile.recentTrend;
    
    // Analyze trend for patterns
    const frustrationCount = trend.filter(t => t === 'FRUSTRATED').length;
    const focusCount = trend.filter(t => t === 'FOCUSED').length;

    let inferredMood = 'STABLE';
    if (frustrationCount > 3) inferredMood = 'HIGH_FRICTION';
    if (focusCount > 5) inferredMood = 'FLOW_STATE';
    
    return {
        inferredMood,
        trend,
        frictionLevel: frustrationCount / trend.length || 0
    };
};
