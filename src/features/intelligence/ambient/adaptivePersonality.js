/**
 * JAOS Phase 7: Adaptive Personality Modulation
 * Dynamically adjusts personality parameters based on environmental and emotional state.
 */

export const modulatePersonality = (state, fatigue, inferredMood) => {
    let params = {
        density: 1.0, // Communication density (1.0 = normal)
        warmth: 0.5,
        energy: 0.5
    };

    // 1. Fatigue Modulation
    if (fatigue > 0.7) {
        params.density = 0.4; // Low density when user is tired
        params.warmth = 0.8;  // High warmth/support
    }

    // 2. State Modulation
    if (state === 'DEEP_WORK') {
        params.density = 0.2; // Minimalist during deep focus
        params.energy = 0.2;
    }

    // 3. Mood Modulation
    if (inferredMood === 'HIGH_FRICTION') {
        params.warmth = 1.0;
        params.density = 0.6;
    }

    return params;
};
