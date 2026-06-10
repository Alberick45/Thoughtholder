/**
 * JAOS Identity Validator (Semantic Firewall)
 * Intercepts AI responses to detect and prevent identity inversion or contamination.
 */

import { IDENTITY_KERNEL } from './IdentityAuthority';

export class IdentityValidator {
    /**
     * Scans a generated response for identity failures.
     * Rejects responses where the AI claims the user's name or identity.
     */
    static validate(response, userIdentity) {
        if (!response) return { valid: true };
        
        const lowerResponse = response.toLowerCase();
        const userName = (userIdentity?.preferred_name || 'User').toLowerCase();
        const aiName = (IDENTITY_KERNEL.AI.canonical_identity || 'Jarvis').toLowerCase();

        // 1. Check for IDENTITY INVERSION (The AI claiming to BE the USER)
        const inversionPatterns = [
            `i am ${userName}`,
            `i'm ${userName}`,
            `my name is ${userName}`,
            `as ${userName}`,
            `i am your ambient ai companion, ${userName}`
        ];

        for (const pattern of inversionPatterns) {
            if (lowerResponse.includes(pattern)) {
                // EXCEPTION: If the user explicitly asked to rename the AI to their own name (rare but possible)
                // For now, we stick to the boundary rule.
                return {
                    valid: false,
                    reason: 'IDENTITY_INVERSION',
                    details: `AI attempted to claim user name: ${userName}`
                };
            }
        }

        // 2. Allow DISPLAY NAMES
        // We no longer reject the AI calling itself its current display name (e.g., Iris)
        // We only reject it if it claims to be the HUMAN/USER.

        // 2. Check for Role Inversion
        if (lowerResponse.includes(`i am the user`) || lowerResponse.includes(`as a human`)) {
            return {
                valid: false,
                reason: 'ROLE_INVERSION',
                details: 'AI attempted to claim human status'
            };
        }

        // 3. Ownership Contamination
        // If the AI speaks about its own "memories" using the user's personal context
        // This is harder to catch but we can look for specific semantic overlaps if needed.

        return { valid: true };
    }
}
