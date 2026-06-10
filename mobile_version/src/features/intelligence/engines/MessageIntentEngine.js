/**
 * JAOS Phase 3: Message Understanding Engine
 * Responsibility: Determining user intent and conversational state.
 * Enables specialized handling for greetings, tasks, and queries.
 */

export const INTENTS = {
    GREETING: 'GREETING',
    IDENTITY_QUERY: 'IDENTITY_QUERY',
    TASK_QUERY: 'TASK_QUERY',
    KNOWLEDGE_QUERY: 'KNOWLEDGE_QUERY',
    CASUAL: 'CASUAL',
    SYSTEM_COMMAND: 'SYSTEM_COMMAND'
};

export class MessageIntentEngine {
    /**
     * Classifies the raw input into a primary intent.
     */
    static classify(text) {
        const input = text.trim().toLowerCase();

        // 1. GREETINGS
        const greetingPatterns = /^(hi|hello|hey|greetings|sup|good morning|good afternoon|good evening|yo)$|^(hi|hello)\s+(jarvis|there)$/i;
        if (greetingPatterns.test(input)) return INTENTS.GREETING;

        // 2. IDENTITY QUERIES (SELF)
        if (/(who am i|do you know my name|what's my name|what is my name)/i.test(input)) return INTENTS.IDENTITY_QUERY;

        // 3. HOW ARE YOU
        if (/(how are you|how's it going|how are you doing|you doing ok)/i.test(input)) return INTENTS.CASUAL;

        // 4. TASK QUERIES
        const taskPatterns = /(what do i have today|any tasks|my to-do|remind me|agenda|schedule)/i;
        if (taskPatterns.test(input)) return INTENTS.TASK_QUERY;

        // 5. SYSTEM COMMANDS
        if (input.startsWith('/') || input.startsWith('!')) return INTENTS.SYSTEM_COMMAND;

        // Default to Casual Conversation
        return INTENTS.CASUAL;
    }

    /**
     * Specialized Greeting Handler (Phase 1.5)
     */
    static getGreetingResponse(userName = 'Friend', input = '') {
        const text = input.toLowerCase();

        if (text.includes('how are you')) {
            return "I'm doing well, thank you for asking! How about you?";
        }

        if (text.includes('who am i') || text.includes('my name')) {
            return `You're ${userName}. Is there something specific I can help you with?`;
        }

        const greetings = [
            `Hey ${userName}!`,
            `Hi ${userName}!`,
            `Hello!`,
            `Hey ${userName}! Nice to see you.`
        ];
        return greetings[Math.floor(Math.random() * greetings.length)];
    }
}
