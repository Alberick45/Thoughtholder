/**
 * JAOS Phase 2: Behavioral Primitive Module
 * Replaces rule-heavy directives with weighted cognitive laws.
 */

import { getPrimitivesPrompt } from '../primitives/CognitivePrimitives';

export const getBehavioralPrompt = (weights, fatigue) => {
  const fatigueDesc = fatigue > 0.7 ? "User is reaching high fatigue." : "User energy levels appear stable.";
  
  return `
${getPrimitivesPrompt(weights)}

[CURRENT STATE OVERVIEW]
- Fatigue Context: ${fatigueDesc} (Score: ${fatigue})
- Communication Strategy: Your behavior must emerge from the weights listed above.
- Tone: Natural, human-peer, ambient. Avoid conversational clichés.
`;
};
