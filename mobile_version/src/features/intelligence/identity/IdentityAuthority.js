/**
 * JAOS Identity Authority
 * The absolute source of truth for system and user identity.
 * Enforces separation between selfhood and memory.
 */

import { db } from '../../../shared/infrastructure/db';

export const IDENTITY_KERNEL = {
    AI: {
        internal_id: 'JAOS_CORE_001',
        canonical_identity: 'Jarvis Autonomous Operating System',
        role: 'Autonomous Operating System',
        version: '4.0',
        system_type: 'Cognitive Runtime',
        immutable_traits: ['analytical', 'ambient', 'proactive', 'protective']
    },
    USER_DEFAULTS: {
        canonical_name: null, // Removed hardcoded 'Albert'
        preferred_name: 'Friend',
        aliases: []
    }
};

class IdentityAuthority {
    constructor() {
        this.cache = null;
    }

    /**
     * Retrieves the protected identity state.
     * Enforces the distinction between Persistent Identity and Presentation.
     */
    async getAuthorityState() {
        if (this.cache) return this.cache;

        const stored = await db.settings.get('jaos_identity_authority');
        const state = stored ? (typeof stored.value === 'string' ? JSON.parse(stored.value) : stored.value) : {
            ai: { 
                ...IDENTITY_KERNEL.AI,
                display_name: 'Jarvis' // Default display name
            },
            user: { ...IDENTITY_KERNEL.USER_DEFAULTS }
        };

        // ENFORCEMENT: Re-inject immutable kernel attributes to prevent drift
        state.ai.internal_id = IDENTITY_KERNEL.AI.internal_id;
        state.ai.canonical_identity = IDENTITY_KERNEL.AI.canonical_identity;
        state.ai.role = IDENTITY_KERNEL.AI.role;
        state.ai.system_type = IDENTITY_KERNEL.AI.system_type;

        this.cache = state;
        return state;
    }

    /**
     * Updates AI display preferences without touching the internal kernel.
     */
    async updateAIDisplay(updates) {
        const state = await this.getAuthorityState();
        if (updates.display_name) state.ai.display_name = updates.display_name;
        if (updates.theme) state.ai.theme = updates.theme;

        await db.settings.put({ key: 'jaos_identity_authority', value: state });
        this.cache = state;
        console.log(`[IDENTITY_AUTHORITY] AI Display Updated: ${state.ai.display_name}`);
    }

    /**
     * Updates user identity state.
     */
    async updateUserIdentity(updates) {
        const state = await this.getAuthorityState();
        if (updates.user_name) state.user.preferred_name = updates.user_name;
        if (updates.canonical_name) state.user.canonical_name = updates.canonical_name;
        if (updates.aliases) state.user.aliases = updates.aliases;

        await db.settings.put({ key: 'jaos_identity_authority', value: state });
        this.cache = state;
    }

    /**
     * Emergency Recovery: Resets identity to the immutable kernel.
     */
    async recoverKernel() {
        const state = {
            ai: { 
                ...IDENTITY_KERNEL.AI,
                display_name: 'Jarvis'
            },
            user: { ...IDENTITY_KERNEL.USER_DEFAULTS }
        };
        await db.settings.put({ key: 'jaos_identity_authority', value: state });
        this.cache = state;
        console.warn("[IDENTITY_AUTHORITY] Kernel Recovery Executed.");
    }
}

export const identityAuthority = new IdentityAuthority();
