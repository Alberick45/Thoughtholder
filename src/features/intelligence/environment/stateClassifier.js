/**
 * JAOS Phase 4: State Classifier
 * Maps raw sensor data to high-level cognitive states.
 */

export const classifyState = (snapshot) => {
    const { window, input, context } = snapshot;

    // 1. Detect Emergency (High urgency system flags - mocked)
    if (context.currentTask.includes('EMERGENCY')) return 'EMERGENCY';

    // 2. Detect Deep Work
    if (window.isFocused && input.keyboardActivity === 'HIGH') {
        return 'DEEP_WORK';
    }

    // 3. Detect Study
    if (window.isFocused && context.currentTask.includes('Study')) {
        return 'STUDY';
    }

    // 4. Detect Stress (Based on high activity + low momentum)
    if (input.keyboardActivity === 'HIGH' && context.currentMomentum < 0.3) {
        return 'STRESS';
    }

    // 5. Detect Idle
    if (input.mouseActivity === 'INACTIVE' && input.keyboardActivity === 'INACTIVE') {
        return 'IDLE';
    }

    // 6. Default fallback
    return 'IDLE';
};
