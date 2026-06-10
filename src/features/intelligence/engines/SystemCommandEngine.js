/**
 * JAOS Phase 5: System Command Engine
 * Responsibility: Executing privileged system operations.
 */

import { db } from '../../../shared/infrastructure/db';

export class SystemCommandEngine {
    /**
     * Executes a recognized system command.
     */
    static async execute(commandText) {
        const cmd = commandText.trim().toLowerCase();
        console.log(`[SYSTEM_COMMAND] Received: "${cmd}"`);

        // 1. DATABASE RESET (Nuclear)
        if (cmd === '/reset_db' || cmd === '/nuclear') {
            console.log("[SYSTEM_COMMAND] Match: Nuclear Wipe");
            return await this.nuclearReset();
        }

        // 2. MEMORY CLEAR
        if (cmd === '/clear_memory' || cmd === '/clear' || cmd === '/cleardemo') {
            console.log("[SYSTEM_COMMAND] Match: Memory Clear");
            return await this.clearMemory();
        }

        // 3. DOCS CLEAR
        if (cmd === '/cleardocs') {
            console.log("[SYSTEM_COMMAND] Match: Docs Clear");
            return await this.clearDocs();
        }

        // 4. AUTH RESET
        if (cmd === '/reset_auth') {
            console.log("[SYSTEM_COMMAND] Match: Auth Reset");
            return await this.resetAuth();
        }

        return `Unknown command: ${cmd}. Type /help for available operations.`;
    }

    /**
     * Wipes ALL structured memory and identity state.
     */
    static async nuclearReset() {
        console.warn("[SYSTEM_COMMAND] Executing NUCLEAR RESET...");
        
        // 1. Wipe Facts & History
        await db.thoughts.where('type').anyOf('profile_fact', 'preference', 'conversation_summary', 'jarvis_log').delete();
        
        // 2. Wipe Identity Authority
        await db.settings.where('key').equals('jaos_identity_authority').delete();
        
        return "Nuclear reset complete. Cognitive architecture and chat history initialized to zero-state.";
    }

    /**
     * Clears only conversational memory (facts/summaries) and UI feed.
     */
    static async clearMemory() {
        console.log("[SYSTEM_COMMAND] Clearing conversational memory and feed...");
        await db.thoughts.where('type').anyOf('profile_fact', 'conversation_summary').delete();
        await this.trashFeed();
        return "Memory purged and feed archived. Jarvis is now operating with a clean slate.";
    }

    /**
     * Eradicates the internal documentation vault.
     */
    static async clearDocs() {
        console.warn("[SYSTEM_COMMAND] Clearing Documentation Vault...");
        await db.documents.clear();
        return "Documentation vault eradicated.";
    }

    /**
     * Hard reset of the Vault security configuration.
     */
    static async resetAuth() {
        console.warn("[SYSTEM_COMMAND] Resetting Auth Config...");
        await db.settings.where('key').anyOf('vault_passcode', 'security_questions', 'recovery_codeword', 'hydraConfigs', 'hydraTriggers', 'hydra_metadata', 'hydra_secrets').delete();
        return "Vault security configuration (Level 4 Deep Guard) has been reset to factory defaults.";
    }

    /**
     * Moves current chat logs to trash status.
     */
    static async trashFeed() {
        console.log("[SYSTEM_COMMAND] Trashing chat feed...");
        await db.thoughts.where('type').equals('jarvis_log').modify({ status: 'trash' });
        return "Chat logs archived to Deep Trash.";
    }
}
