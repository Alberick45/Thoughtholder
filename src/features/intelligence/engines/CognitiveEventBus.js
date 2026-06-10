/**
 * JAOS Cognitive Event Bus
 * The asynchronous backbone for all cognitive signals.
 */

class CognitiveEventBus {
    constructor() {
        this.subscribers = {};
    }

    /**
     * Subscribe to a cognitive signal.
     */
    subscribe(event, callback) {
        if (!this.subscribers[event]) {
            this.subscribers[event] = [];
        }
        this.subscribers[event].push(callback);
        return () => {
            this.subscribers[event] = this.subscribers[event].filter(cb => cb !== callback);
        };
    }

    /**
     * Publish a cognitive signal.
     */
    publish(event, data) {
        if (!this.subscribers[event]) return;
        this.subscribers[event].forEach(callback => {
            try {
                callback(data);
            } catch (err) {
                console.error(`[EVENT_BUS] Error in subscriber for ${event}:`, err);
            }
        });
    }

    /**
     * Common Events:
     * - USER_INPUT
     * - MODEL_THINKING (Streamed monologue)
     * - MODEL_RESPONSE (Final text)
     * - COGNITIVE_STATE_SHIFT
     * - RELATIONAL_EVOLUTION
     * - MEMORY_LINKED
     * - AMBIENT_INSIGHT
     */
}

export const bus = new CognitiveEventBus();
