/**
 * JAOS Phase 4: Fatigue Estimator
 * Models user energy depletion based on session duration and task intensity.
 */

export const estimateFatigue = (stateHistory) => {
    // stateHistory is an array of [state, timestamp]
    if (stateHistory.length < 2) return 0.1;

    const sessionStart = stateHistory[0][1];
    const now = Date.now();
    const durationHours = (now - sessionStart) / (1000 * 60 * 60);

    // Intensity weighted average
    const intensityMap = {
        DEEP_WORK: 1.0,
        STUDY: 0.8,
        STRESS: 1.2,
        IDLE: 0.1,
        RECOVERY: -0.2 // Recovery reduces fatigue
    };

    let totalIntensity = 0;
    stateHistory.forEach(([state]) => {
        totalIntensity += (intensityMap[state] || 0.5);
    });

    const averageIntensity = totalIntensity / stateHistory.length;
    const fatigueScore = Math.min(1.0, (durationHours * 0.2) * averageIntensity);

    return fatigueScore;
};
