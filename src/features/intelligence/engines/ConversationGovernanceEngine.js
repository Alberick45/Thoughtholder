/**
 * JAOS Phase 1.5: Conversation Governance Engine
 * Responsibility: Enforcing natural conversation scale and preventing hallucinations.
 * Implements Rule 1-10 of the Governance Protocol.
 */

export class ConversationGovernanceEngine {
    /**
     * Governs the response before it is displayed.
     * Scales the length and validates context boundaries.
     */
    static govern(input, response, intent) {
        if (!response) return "";

        let governed = response.trim();

        // RULE 1 & 8: RESPONSE SCALING
        const inputWords = input.trim().split(/\s+/).length;
        
        // If input is very short (1-3 words) and response is an essay, we truncate or flag
        if (inputWords <= 3 && governed.split(/\s+/).length > 30 && intent !== 'TASK_QUERY') {
            console.warn("[GOVERNANCE] Response too verbose for short input. Truncating to first two sentences.");
            governed = governed.split(/[.!?]\s/).slice(0, 2).join('. ') + '.';
        }

        // RULE 2 & 7: HALLUCINATION & CONTEXT BOUNDARY CHECK
        const illegalContexts = [
            'our company', 
            'our development process', 
            'your project struggles', 
            'development team', 
            'technical issues faced',
            'management at our',
            'how may we proceed'
        ];

        for (const context of illegalContexts) {
            if (governed.toLowerCase().includes(context)) {
                console.warn(`[GOVERNANCE] Illegal context detected: "${context}". Stripping hallucinated segment.`);
                // Strip the sentence containing the hallucination
                const sentences = governed.split(/(?<=[.!?])\s+/);
                governed = sentences.filter(s => !s.toLowerCase().includes(context)).join(' ');
            }
        }

        // RULE 5: BULLET POINT ENFORCEMENT
        if (inputWords < 5 && (governed.includes('*') || governed.includes('- ')) && intent === 'GREETING') {
            console.warn("[GOVERNANCE] Stripping unsolicited bullet points from greeting.");
            governed = governed.replace(/^\s*[*+-]\s+/gm, '').replace(/\n/g, ' ');
        }

        return governed.trim();
    }

    /**
     * Injects Governance Rules into the system prompt.
     */
    static getGovernanceDirectives() {
        return `
[CONVERSATION GOVERNANCE PROTOCOL]:
1. RESPOND PROPORTIONALLY: Small input = small response.
2. NO HALLUCINATED CONTEXT: Do not invent companies, projects, or technical struggles.
3. BE NATURAL: Avoid robotic or corporate phrasing.
4. NO BULLETS: Unless explicitly asked for a list or task summary.
5. GROUNDING: Anchor replies ONLY to the current input and verified memory.
`.trim();
    }
}
