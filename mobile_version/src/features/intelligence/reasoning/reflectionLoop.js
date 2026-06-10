/**
 * JAOS Phase 6: Reflection Loop (Orchestrator)
 * The central engine for background internal cognition and self-reflection.
 */

import { inferMoodState } from './emotionalReasoner';
import { getActiveGoals } from './goalTracker';
import { getUnresolvedLoops } from './unresolvedLoopTracker';
import { generateInternalMonologue } from './internalMonologue';

export const runReflectionLoop = async (lastInteraction) => {
    // 1. Update Inferred State
    const emotionalState = await inferMoodState();
    const goals = await getActiveGoals();
    const loops = await getUnresolvedLoops();
    
    // 2. Synthesize Internal State
    const internalState = {
        inferredMood: emotionalState.inferredMood,
        activeGoals: goals,
        unresolvedLoops: loops,
        probableIntent: lastInteraction?.probableIntent || 'Unknown',
        momentum: lastInteraction?.momentum || 'Stable'
    };
    
    // 3. Generate Monologue
    const monologue = generateInternalMonologue(internalState);
    
    return {
        internalState,
        monologue
    };
};
