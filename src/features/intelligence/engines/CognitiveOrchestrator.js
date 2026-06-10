/**
 * JAOS Cognitive Orchestrator
 * Calculates the weights for cognitive primitives based on system state.
 */

export class CognitiveOrchestrator {
    static calculateWeights(jaosState, fatigue, momentum, depth) {
        const weights = {
            RHYTHM: 1.0,
            GRAVITY: 1.0,
            DENSITY: 1.0,
            ANCHORING: 1.0,
            DEPTH: 1.0,
            LEASH: 1.0,
            WARMTH: 1.0
        };

        // 1. Adjust GRAVITY (Attention)
        if (jaosState === 'DEEP_FOCUS') {
            weights.GRAVITY = 2.0; // High silence/interruption cost
            weights.DENSITY = 0.5; // Brief responses
            weights.WARMTH = 0.5;  // More professional/efficient
        } else if (jaosState === 'IDLE' || jaosState === 'SLEEP') {
            weights.GRAVITY = 0.5; // More conversational/ambient
            weights.WARMTH = 1.5;  // More casual/warm
        }

        // 2. Adjust DENSITY (Verbosity)
        if (fatigue > 0.7) {
            weights.DENSITY = 0.4; // User is tired, speak less
            weights.RHYTHM = 0.5;  // Slower interaction
        }

        // 3. Adjust DEPTH (Memory)
        if (momentum === 'Stagnant') {
            weights.DEPTH = 2.0; // Try to bring in more semantic/episodic context to spark ideas
        }

        // 4. Adjust WARMTH (Relationship)
        // Based on relational depth (STRANGER, COMPANION, PEER, ALIGNMENT)
        if (depth === 'STRANGER') weights.WARMTH = 0.8;
        if (depth === 'ALIGNMENT') weights.WARMTH = 2.0;

        return weights;
    }
}
