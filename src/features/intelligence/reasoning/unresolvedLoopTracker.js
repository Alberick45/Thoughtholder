/**
 * JAOS Phase 6: Unresolved Loop Tracker
 * Tracks "Open Loops"—questions or tasks that haven't reached closure.
 */

import { db } from '../../../shared/infrastructure/db';

export const getUnresolvedLoops = async () => {
    try {
        const loops = await db.thoughts
            .filter(t => t.tags?.includes('unfinished_loop') || (t.type === 'task' && t.status === 'fresh'))
            .toArray();
        return loops;
    } catch (error) {
        console.error("[LOOP_TRACKER] Retrieval error:", error);
        return [];
    }
};

export const closeLoop = async (id) => {
    const thought = await db.thoughts.get(id);
    if (thought) {
        const newTags = (thought.tags || []).filter(tag => tag !== 'unfinished_loop');
        await db.thoughts.update(id, { tags: newTags, status: 'archived' });
    }
};
