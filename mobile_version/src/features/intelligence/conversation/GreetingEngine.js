/**
 * JAOS Phase 2: Natural Conversation Engine (Greetings)
 * Responsibility: Generating friendly, grounded greetings.
 * Ensures the system feels conversational first.
 */

export class GreetingEngine {
    static async generate(userName = 'Friend', input = '') {
        const text = input.toLowerCase();
        
        // Dynamic summary fallback
        if (text.includes('todo') || text.includes('task') || text.includes('list')) {
            const { db } = await import('../../../shared/infrastructure/db');
            const tasks = await db.thoughts.filter(t => t.type === 'task' && t.status !== 'trash' && t.status !== 'archived').toArray();
            if (tasks.length === 0) return "You have no pending tasks right now. Great job!";
            return `You have ${tasks.length} pending tasks. Top item: "${tasks[0].content.split('\n')[0]}".`;
        }
        
        if (text.includes('buy') || text.includes('shopping')) {
            const { db } = await import('../../../shared/infrastructure/db');
            const items = await db.thoughts.filter(t => t.type === 'buy' && t.status !== 'trash' && t.status !== 'archived').toArray();
            if (items.length === 0) return "Your shopping list is empty.";
            return `You have ${items.length} items on your buy list. Items include: ${items.slice(0,3).map(i => i.content.split('\n')[0]).join(', ')}...`;
        }

        if (text.includes('how are you')) {
            return "I'm running optimally on your device's local kernel. Ready for your instructions!";
        }

        if (text.includes('who am i') || text.includes('my name')) {
            return `You're ${userName}. Anything I can help you with right now?`;
        }

        const greetings = [
            `Hey ${userName}!`,
            `Hi ${userName}!`,
            `Hello ${userName}!`,
            `Hey ${userName}, how's your day going?`
        ];

        return greetings[Math.floor(Math.random() * greetings.length)];
    }
}
