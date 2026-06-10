/**
 * JAOS Phase 2: Natural Conversation Engine (Greetings)
 * Responsibility: Generating friendly, grounded greetings.
 * Ensures the system feels conversational first.
 */

export class GreetingEngine {
    static generate(userName = 'Friend', input = '') {
        const text = input.toLowerCase();

        if (text.includes('how are you')) {
            return "I'm doing well, thank you for asking! How are you doing today?";
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
