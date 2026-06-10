/**
 * JAOS Phase 2: Semantic Memory Module
 * Manages the persistent knowledge base, facts, and conceptual relationships.
 */

import { db } from '../../../shared/infrastructure/db';

export const getSemanticContext = async (queryVec, threshold = 0.3, limit = 5) => {
    try {
        const { cosineSimilarity } = await import('../services/embeddings');
        const allThoughts = await db.thoughts.toArray();
        
        const results = allThoughts
            .filter(t => t.embedding && t.status !== 'trash')
            .map(t => ({
                ...t,
                similarity: cosineSimilarity(queryVec, t.embedding)
            }))
            .filter(t => t.similarity > threshold)
            .sort((a, b) => b.similarity - a.similarity)
            .slice(0, limit);
            
        return results;
    } catch (error) {
        console.error("[SEMANTIC_MEMORY] Retrieval error:", error);
        return [];
    }
};

export const updateSemanticLink = async (id1, id2, relationshipType = 'related') => {
    // Updates link metadata between two semantic nodes
    const t1 = await db.thoughts.get(id1);
    if (t1) {
        const links = t1.linked_thoughts || [];
        if (!links.includes(id2)) {
            await db.thoughts.update(id1, { linked_thoughts: [...links, id2] });
        }
    }
};
