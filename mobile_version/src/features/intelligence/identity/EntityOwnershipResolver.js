/**
 * JAOS Entity Ownership Resolver
 * Determines the target and intent of identity-related conversational inputs.
 * Prevents "Naming Collision" where the user renaming themselves is confused with renaming the AI.
 */

export const ENTITY_TYPES = {
    USER: 'USER',
    AI_DISPLAY: 'AI_DISPLAY',
    SYSTEM_KERNEL: 'SYSTEM_KERNEL'
};

export const INTENT_TYPES = {
    SELF_IDENTIFICATION: 'SELF_IDENTIFICATION',
    ENTITY_RENAMING: 'ENTITY_RENAMING',
    IDENTITY_REFERENCE: 'IDENTITY_REFERENCE'
};

export class EntityOwnershipResolver {
    /**
     * Analyzes the input to determine ownership direction.
     * @param {string} input - The raw user input.
     * @returns {Object} { target, intent, value }
     */
    static resolve(input) {
        const text = input.trim().toLowerCase();
        
        // 1. User Self-Identification Patterns
        const userPatterns = [
            /^(?:call me|my name is|i am|i'm|just call me|people call me)\s+([\w\s'-]+)[.!?]*$/i,
            /^(?:it's|this is)\s+([\w\s'-]+)[.!?]*$/i
        ];

        for (const pattern of userPatterns) {
            const match = text.match(pattern);
            if (match) {
                return {
                    target: ENTITY_TYPES.USER,
                    intent: INTENT_TYPES.SELF_IDENTIFICATION,
                    value: match[1].trim()
                };
            }
        }

        // 2. AI Display-Name Customization
        const aiPatterns = [
            /^(?:can i call you|you are|your name is|i will call you|from now on you are)\s+([\w\s'-]+)[.!?]*$/i,
            /^(?:your name will be|i'm naming you)\s+([\w\s'-]+)[.!?]*$/i
        ];

        for (const pattern of aiPatterns) {
            const match = text.match(pattern);
            if (match) {
                let val = match[1].replace(/\?$/, '').trim();
                return {
                    target: ENTITY_TYPES.AI_DISPLAY,
                    intent: INTENT_TYPES.ENTITY_RENAMING,
                    value: val
                };
            }
        }

        // 3. Simple Naming (Contextual)
        // If the user just says a name, we treat it as a reference unless we are in an onboarding state.
        
        return {
            target: null,
            intent: INTENT_TYPES.IDENTITY_REFERENCE,
            value: null
        };
    }
}
