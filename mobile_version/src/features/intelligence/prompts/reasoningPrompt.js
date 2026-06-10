/**
 * JAOS Phase 6: Reasoning Module (Prompt)
 * Injects internal thought loops and reflection data into the system prompt.
 */

export const getReasoningPrompt = (internalState, monologue) => {
  if (!internalState) return '';

  const forecast = JSON.parse(localStorage.getItem('jaos_forecast') || '{}');
  const habits = JSON.parse(localStorage.getItem('jaos_habits') || '{}');

  return `
[INTERNAL COGNITION]
${monologue}

[PREDICTIVE FORECASTING]
- Upcoming Roadblock: ${forecast.predictedRoadblock || 'None'}
- Suggested Prep: ${forecast.suggestedPreparation || 'Maintain current path.'}
- Detected Habit: ${habits.energyPattern || 'Unknown Pattern'} (Peak: ${habits.peakActivityHour}:00)

[GOAL PERSISTENCE]
Active Priorities: ${internalState.activeGoals.map(g => g.content).join(', ') || 'Maintain ambient support.'}

[LOOP TRACKING]
Unresolved Items: ${internalState.unresolvedLoops.length} items pending closure.
`;
};
