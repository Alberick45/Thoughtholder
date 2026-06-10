/**
 * JAOS Phase 4: System Awareness Engine (Task Module)
 * Responsibility: Retrieving and summarizing actual tracked tasks.
 * Prevents hallucinated productivity analysis.
 */

import { db } from '../../../shared/infrastructure/db';

export class TaskEngine {
    /**
     * Retrieves actual tasks from the database and returns a natural summary.
     */
    static async getTaskSummary() {
        try {
            const activeTasks = await db.thoughts
                .filter(t => t.type === 'task' && (t.status === 'fresh' || t.status === 'active'))
                .limit(10)
                .toArray();

            if (activeTasks.length === 0) {
                return "You don't have any active tasks on your list right now. Anything new you'd like to capture?";
            }

            const taskList = activeTasks.map(t => `- ${t.content}`).join('\n');
            return `You have ${activeTasks.length} active tasks:\n\n${taskList}\n\nWhat would you like to focus on?`;
        } catch (error) {
            console.error("[TASK_ENGINE] Retrieval error:", error);
            return "I'm having a bit of trouble reaching your task list right now. One moment.";
        }
    }
}
