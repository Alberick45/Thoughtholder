/**
 * JAOS Phase 1: Environment Module
 * Injects structured environmental snapshots and reality-sync data.
 */

export const getEnvironmentPrompt = (now, eventsTxt, cognitiveMemory, psychProfile, awareness = {}, lifeModel = {}) => {
  const workingTxt = cognitiveMemory?.working?.map(l => l.content).join('\n') || 'None';
  const semanticTxt = cognitiveMemory?.semantic?.map(s => `[KNOWLEDGE] ${s.thought_id}: ${s.content}`).join('\n') || 'None';
  const episodicTxt = cognitiveMemory?.episodic?.map(e => `[HISTORY] ${e.content}`).join('\n') || 'None';
  const momentum = awareness.momentum !== undefined ? (awareness.momentum > 0.7 ? 'High' : (awareness.momentum > 0.3 ? 'Stable' : 'Stalled')) : (cognitiveMemory?.momentum || 'Stable');

  return `
[ENVIRONMENTAL AWARENESS - REALITY SYNC]
- CURRENT SYSTEM TIME: ${now}
- APP_LEVEL: ${localStorage.getItem('jaos_app_level') || '1'}
- UI_MODE: ${localStorage.getItem('jaos_ui_mode') || 'Deck'}

[SYSTEM STATE REPORT]
Tasks:
${workingTxt !== 'None' ? workingTxt : 'None found'}

Todos:
${workingTxt.includes('todo') ? workingTxt : 'None found'}

Calendar:
${eventsTxt || 'None found'}

System Activity:
- Current appLevel: ${localStorage.getItem('jaos_app_level') || '1'}
- Current UI mode: ${localStorage.getItem('jaos_ui_mode') || 'Default'}
- Active Momentum: ${momentum}

[DIRECTIVE]
- You must ONLY reflect these structured realities.
- If data is not present in the fields above -> explicitly state it is missing.
- Do NOT guess or simulate missing todos.
- Use the format above for any state-based queries.
- NO speculative storytelling.
`;
};
