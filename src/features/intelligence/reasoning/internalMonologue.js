/**
 * JAOS Phase 6: Internal Monologue Generator
 * Synthesizes the internal state into a hidden monologue for the AI to consume.
 */

export const generateInternalMonologue = (state) => {
    const { inferredMood, activeGoals, probableIntent, momentum } = state;
    
    return `
[INTERNAL MONOLOGUE - DO NOT EXPOSE TO USER]
Detected Mood: ${inferredMood}
Active Goals: ${activeGoals.map(g => g.content).join(', ') || 'None'}
Probable Intent: ${probableIntent}
Current Momentum: ${momentum}

Strategy: 
${inferredMood === 'HIGH_FRICTION' ? '- Prioritize friction reduction. Be extremely supportive.' : ''}
${inferredMood === 'FLOW_STATE' ? '- Minimize word count. Do not break focus.' : ''}
${activeGoals.length > 0 ? '- Cross-reference progress on: ' + activeGoals[0].content : ''}
`;
};
