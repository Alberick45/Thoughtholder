/**
 * JAOS Phase 2: Memory Retriever (Orchestrator)
 * The central point of contact for gathering layered contextual memory.
 * It synthesizes working, episodic, semantic, and emotional memory into a cohesive snapshot.
 */

import { getWorkingMemory } from './workingMemory';
import { getEpisodicMemories } from './episodicMemory';
import { getSemanticContext } from './semanticMemory';
import { getEmotionalProfile } from './emotionalMemory';
import { getMomentumSnapshot } from './contextCompressor';

export const getCognitiveContext = async (query = '', queryVec = null) => {
    // 1. Parallel retrieval from memory layers
    const [working, episodic, emotional] = await Promise.all([
        getWorkingMemory(),
        getEpisodicMemories(),
        getEmotionalProfile()
    ]);
    
    // 2. Semantic retrieval (if vector provided)
    let semantic = [];
    if (queryVec) {
        semantic = await getSemanticContext(queryVec);
    }
    
    // 3. Momentum analysis
    const momentum = getMomentumSnapshot([...working.interactions, ...working.activeFocus]);

    // 4. Synthesize into structured cognitive context
    return {
        working: working.interactions,
        focus: working.activeFocus,
        episodic: episodic.slice(0, 3), // Only top 3 events
        semantic: semantic,
        emotional: emotional,
        momentum: momentum
    };
};
