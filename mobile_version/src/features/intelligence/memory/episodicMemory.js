/**
 * JAOS Phase 2: Episodic Memory Module
 * Captures sequences of experiences and specific event-based memories.
 */

import { db } from '../../../shared/infrastructure/db';

export const getEpisodicMemories = async (query = '') => {
    try {
        // Episodic memory focuses on events and significant past interactions
        const events = await db.thoughts
            .filter(t => t.type === 'event' && t.status !== 'trash')
            .toArray();
            
        // If a query is provided, we could use semantic search here (future improvement)
        return events;
    } catch (error) {
        console.error("[EPISODIC_MEMORY] Retrieval error:", error);
        return [];
    }
};

export const recordEpisode = async (content, importance = 0.5) => {
    // Logic to record a significant "episode"
    const episode = {
        thought_id: `Episode-${Date.now()}`,
        content,
        type: 'episode',
        status: 'archived',
        importance_score: importance,
        created_at: Date.now()
    };
    return await db.thoughts.add(episode);
};
