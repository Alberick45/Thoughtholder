/**
 * JAOS Phase 5: Autonomy Manager
 * The central decision engine for safe autonomous behavior.
 */

import { calculateConfidence } from './actionConfidence';
import { assessRisk } from './riskAssessment';
import { getExecutionPolicy } from './executionPolicy';

export const evaluateAutonomousAction = (action, context) => {
    // 1. Calculate Confidence
    const confidence = calculateConfidence(
        action, 
        context.evidenceCount || 0, 
        context.semanticRelevance || 0.5
    );

    // 2. Assess Risk
    const risk = assessRisk(action);

    // 3. Get Policy
    const policy = getExecutionPolicy(confidence, risk);

    return {
        action,
        confidence,
        risk,
        policy,
        canProceed: policy.allowExecution
    };
};
