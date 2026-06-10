/**
 * JAOS Sleep Engine
 * Handles low-priority maintenance tasks during system downtime.
 * Compresses memories, consolidates vectors, and archives cognitive clutter.
 */

import { bus } from './CognitiveEventBus';
import { db } from '../../../shared/infrastructure/db';

export class SleepEngine {
    constructor() {
        this.isSleeping = false;
        this.initializeSubscribers();
    }

    initializeSubscribers() {
        // Triggered by Orchestrator on LONG_INACTIVITY
        bus.subscribe('START_MEMORY_COMPRESSION', async () => {
            if (this.isSleeping) return;
            this.isSleeping = true;
            
            try {
                bus.publish('MODEL_THINKING', { step: 'SYSTEM', message: 'Entering sleep mode. Consolidating memories...' });
                await this.performMaintenance();
            } catch (error) {
                console.error("[SLEEP_ENGINE] Maintenance failed:", error);
            } finally {
                this.isSleeping = false;
                bus.publish('TASK_COMPLETE', { type: 'MAINTENANCE' });
            }
        });
    }

    async performMaintenance() {
        // 1. Archive Low-Priority Context (Stale Thoughts)
        const oldThoughts = await db.thoughts
            .filter(t => t.stale_score > 5 && t.status !== 'archived' && t.status !== 'trash')
            .toArray();

        if (oldThoughts.length > 0) {
            console.log(`[SLEEP_ENGINE] Archiving ${oldThoughts.length} stale thoughts.`);
            // In reality, we would batch update these in IndexedDB
            const updates = oldThoughts.map(t => ({ ...t, status: 'archived' }));
            await db.thoughts.bulkPut(updates);
        }

        // 2. Generate Daily Summaries
        const recentLogs = await db.thoughts
            .filter(t => t.type === 'jarvis_log' && (Date.now() - t.created_at) < 86400000)
            .toArray();

        if (recentLogs.length > 20) {
            console.log(`[SLEEP_ENGINE] Generating daily interaction summary for compression.`);
            // Trigger Tier 1 ambient model via router to summarize
            bus.publish('REQUEST_AMBIENT_SUMMARY', { data: recentLogs });
        }

        // 3. Optimize Vector Store (Placeholder for vector cleanup)
        // e.g. deleting orphaned embeddings or merging similar nodes
        
        bus.publish('MODEL_THINKING', { step: 'SYSTEM', message: 'Sleep maintenance complete. Standing by.' });
    }
}

export const sleepEngine = new SleepEngine();
