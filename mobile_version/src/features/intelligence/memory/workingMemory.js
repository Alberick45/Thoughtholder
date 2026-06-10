/**
 * JAOS Phase 2: Working Memory Module
 * Handles short-term context, recent interaction tracking, and unfinished loops.
 */

import { db } from '../../../shared/infrastructure/db';

export const getWorkingMemory = async (limit = 10) => {
    try {
        // Working memory is typically the last X interactions and currently active tasks
        const recentLogs = await db.thoughts
            .where('type').equals('jarvis_log')
            .reverse()
            .limit(limit)
            .toArray();

        // SCRUBBER: Prevent garbage feedback loops in memory
        const scrubbedLogs = recentLogs.map(log => {
            let content = log.content || '';
            // Remove the **You:** and **Jarvis:** prefixes for memory efficiency
            content = content.replace(/^\*\*(You|Jarvis):\*\*\n?/g, '');
            // Remove any leaked system tags or tags like <INTERNAL_MONOLOGUE>
            content = content.replace(/<[^>]*>[\s\S]*?<\/[^>]*>/gi, '')
                             .replace(/^(assistant|user|system):\s*/gim, '')
                             .trim();
            return { ...log, content };
        });
            
        const activeTasks = await db.thoughts
            .filter(t => t.type === 'task' && (t.status === 'fresh' || t.status === 'active'))
            .limit(5)
            .toArray();

        return {
            interactions: scrubbedLogs.reverse(), // Put back in chronological order
            activeFocus: activeTasks
        };
    } catch (error) {
        console.error("[WORKING_MEMORY] Retrieval error:", error);
        return { interactions: [], activeFocus: [] };
    }
};

export const updateUnfinishedLoops = async (thought) => {
    // Logic to detect if a thought represents an unfinished loop (e.g. a question asked by user)
    if (thought.type === 'task' || (thought.type === 'thought' && thought.content.includes('?'))) {
        await db.thoughts.update(thought.id, { 
            tags: [...(thought.tags || []), 'unfinished_loop'],
            importance_score: 0.8
        });
    }
};
