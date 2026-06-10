/**
 * JAOS Phase 4: Environment Reasoner
 * Synthesizes sensor data and classifiers into a coherent environmental context.
 */

import { getEnvironmentSnapshot } from './sensorFusion';
import { classifyState } from './stateClassifier';
import { estimateFatigue } from './fatigueEstimator';

export const reasonAboutEnvironment = (stateHistory = []) => {
    const snapshot = getEnvironmentSnapshot();
    const currentState = classifyState(snapshot);
    const fatigue = estimateFatigue(stateHistory);

    return {
        currentState,
        fatigue,
        snapshot,
        isOverloaded: fatigue > 0.8 || currentState === 'STRESS',
        needsBreak: fatigue > 0.7 && currentState !== 'DEEP_WORK'
    };
};
