/**
 * JAOS Phase 3: Attention Policy
 * Defines strict engagement rules for different behavioral states.
 */

export const getAttentionPolicy = (state) => {
    const policies = {
        DEEP_WORK: {
            minBenefitThreshold: 0.8, // Only extremely high value interrupts
            proactiveAllowed: false,
            verbosity: 'CONCISE'
        },
        STUDY: {
            minBenefitThreshold: 0.5,
            proactiveAllowed: true,
            verbosity: 'STRUCTURED'
        },
        IDLE: {
            minBenefitThreshold: 0.1, // Almost anything can be brought up
            proactiveAllowed: true,
            verbosity: 'HUMAN'
        },
        RECOVERY: {
            minBenefitThreshold: 0.3,
            proactiveAllowed: true,
            verbosity: 'LIGHT'
        },
        EMERGENCY: {
            minBenefitThreshold: -1.0, // Always interrupt
            proactiveAllowed: true,
            verbosity: 'URGENT'
        }
    };

    return policies[state] || policies.IDLE;
};
