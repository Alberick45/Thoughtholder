/**
 * JAOS Phase 1: Intent Detector
 * Responsibility: Categorizing user input for optimal routing.
 */

export class IntentDetector {
    detect(text) {
        const input = text.trim().toLowerCase();

        if (/^(hi|hello|hey|sup|yo|greetings)$/i.test(input) || /^(hi|hello)\s+(jarvis|there)$/i.test(input)) {
            return 'GREETING';
        }

        if (/(who am i|do you know my name|what's my name|what is my name)/i.test(input)) {
            return 'IDENTITY';
        }

        if (/(what do i have today|any tasks|my to-do|remind me|agenda|schedule)/i.test(input)) {
            return 'TASK_QUERY';
        }

        if (input.startsWith('/') || input.startsWith('!')) {
            console.log("[INTENT_DETECTOR] COMMAND detected");
            return 'COMMAND';
        }

        console.log("[INTENT_DETECTOR] Defaulting to GENERAL_CHAT");
        return 'GENERAL_CHAT';
    }
}
