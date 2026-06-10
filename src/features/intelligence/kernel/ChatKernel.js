/**
 * JAOS Phase 1: Core Chat Kernel
 * Responsibility: Absolute source of truth for conversational throughput.
 * Ensures clean input/output and coordinates the MessagePipeline.
 */

import { MessagePipeline } from './MessagePipeline';
import { bus } from '../engines/CognitiveEventBus'; // Keeping the event bus for now

export class ChatKernel {
    constructor() {
        this.pipeline = new MessagePipeline();
    }

    /**
     * Entry point for all user messages.
     */
    async execute(query) {
        console.log("[CHAT_KERNEL] Executing query:", query);
        bus.publish('KERNEL_STATUS', { state: 'PROCESSING', query });

        try {
            const result = await this.pipeline.process(query);
            console.log("[CHAT_KERNEL] Execution complete.");
            bus.publish('KERNEL_STATUS', { state: 'IDLE' });
            return result;
        } catch (error) {
            console.error("[CHAT_KERNEL] Critical Failure:", error);
            bus.publish('KERNEL_STATUS', { state: 'ERROR', error: error.message });
            return {
                reply: "I've encountered a system kernel disruption. I'm initiating a localized reset.",
                error: error.message
            };
        }
    }
}

export const chatKernel = new ChatKernel();
