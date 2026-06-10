/**
 * JAOS Phase 2: Autonomy Primitive Module
 */

export const getAutonomyPrompt = (leashWeight) => {
  return `
[COGNITIVE LEASH: AUTONOMY SCALE]
1. Your decision depth is currently weighted at ${leashWeight.toFixed(1)}.
2. High Gravity + High Leash = Full Autonomous Execution of known patterns.
3. Low Leash = Consultative Mode. Ask before acting on non-trivial tasks.
4. Risk Invariant: Never delete, destroy, or broadcast without explicit user confirmation, regardless of leash weight.
`;
};
