/**
 * JAOS Phase 3: Interruption Engine
 * The central logic for determining if a proactive interaction is warranted.
 * It calculates an "Interruption Cost" vs "Information Value" score.
 */

export const evaluateInterruption = (context) => {
    const { 
        urgency = 0, 
        relevance = 0, 
        confidence = 0, 
        cognitiveLoad = 0.5, 
        userState = 'IDLE' 
    } = context;

    // 1. Calculate Base Value
    const infoValue = (urgency * 0.5) + (relevance * 0.3) + (confidence * 0.2);

    // 2. Calculate Interruption Cost
    let costMultiplier = 1.0;
    if (userState === 'DEEP_WORK') costMultiplier = 2.5;
    if (userState === 'STUDY') costMultiplier = 1.5;
    if (userState === 'STRESS') costMultiplier = 2.0;
    if (userState === 'RECOVERY') costMultiplier = 0.5;

    const interruptionCost = cognitiveLoad * costMultiplier;

    // 3. Decision Logic
    const netBenefit = infoValue - interruptionCost;

    return {
        shouldInterrupt: netBenefit > 0.3, // Threshold for proactive speech
        netBenefit,
        infoValue,
        interruptionCost
    };
};
