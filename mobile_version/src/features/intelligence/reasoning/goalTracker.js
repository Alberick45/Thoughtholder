/**
 * JAOS Phase 6: Goal Tracker
 * Monitors long-term and short-term user objectives.
 */

import { db } from '../../../shared/infrastructure/db';

export const getActiveGoals = async () => {
    try {
        // Goals are stored in the thoughts table with a specific tag or type
        const goals = await db.thoughts
            .filter(t => t.tags?.includes('goal') && t.status !== 'archived' && t.status !== 'trash')
            .toArray();
        return goals;
    } catch (error) {
        console.error("[GOAL_TRACKER] Retrieval error:", error);
        return [];
    }
};

export const updateGoalProgress = async (goalId, progressDelta) => {
    const goal = await db.thoughts.get(goalId);
    if (goal) {
        const newProgress = Math.min(1.0, (goal.progress || 0) + progressDelta);
        await db.thoughts.update(goalId, { progress: newProgress });
        if (newProgress === 1.0) {
            await db.thoughts.update(goalId, { status: 'archived' });
        }
    }
};
