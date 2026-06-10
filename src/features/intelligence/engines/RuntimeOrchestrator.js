/**
 * JAOS Runtime Orchestrator
 * Maps system events to cognitive engines and manages asynchronous execution.
 */

import { bus } from './CognitiveEventBus';
import { stateManager, CognitiveStates } from './CognitiveStateManager';
import { ReactiveEngine } from './ReactiveEngine';

export class RuntimeOrchestrator {
    constructor() {
        this.reactiveEngine = new ReactiveEngine();
        this.taskQueue = [];
        this.isProcessingQueue = false;

        this.initializeSubscribers();
    }

    initializeSubscribers() {
        // --- 1. User Interaction Events ---
        bus.subscribe('USER_MESSAGE_RECEIVED', async (payload) => {
            // High priority: preempt idle or maintenance
            const canTransition = stateManager.transitionTo(CognitiveStates.REACTIVE, 'User initiated chat');
            if (canTransition) {
                const response = await this.reactiveEngine.process(payload.query);
                bus.publish('MODEL_RESPONSE_READY', response);
                stateManager.transitionTo(CognitiveStates.IDLE_MONITORING, 'Reactive task complete');
            } else {
                this.queueTask('USER_MESSAGE_RECEIVED', payload, 8);
            }
        });

        // --- 2. Ambient / Idle Events ---
        bus.subscribe('LONG_INACTIVITY', () => {
            if (stateManager.currentState === CognitiveStates.IDLE_MONITORING) {
                stateManager.transitionTo(CognitiveStates.MAINTENANCE, 'Idle maintenance triggered');
                bus.publish('START_MEMORY_COMPRESSION', {});
            }
        });

        // --- 3. Memory & Evolution Events ---
        bus.subscribe('MEMORY_CONFLICT_DETECTED', (payload) => {
            // Queue reflection for later
            this.queueTask('RESOLVE_MEMORY_CONFLICT', payload, 4);
        });

        bus.subscribe('RELATIONSHIP_SHIFT', (payload) => {
            stateManager.transitionTo(CognitiveStates.EMOTIONAL_PROCESSING, 'Relationship depth changed');
            // Trigger ambient model to assess the shift
            bus.publish('UPDATE_RELATIONAL_MODEL', payload);
        });

        // --- 4. Task / Queue Events ---
        bus.subscribe('TASK_COMPLETE', () => {
            this.processNextInQueue();
        });
    }

    /**
     * Async Task Orchestration
     * Queues lower priority events if the system is busy in a high-priority state.
     */
    queueTask(eventName, payload, priority) {
        this.taskQueue.push({ eventName, payload, priority });
        // Sort by priority descending
        this.taskQueue.sort((a, b) => b.priority - a.priority);
        console.log(`[ORCHESTRATOR] Queued event ${eventName} at priority ${priority}`);
    }

    async processNextInQueue() {
        if (this.isProcessingQueue || this.taskQueue.length === 0) return;
        
        // Only process if in a state that allows interruptions
        if (![CognitiveStates.IDLE_MONITORING, CognitiveStates.MAINTENANCE].includes(stateManager.currentState)) {
            return;
        }

        this.isProcessingQueue = true;
        const task = this.taskQueue.shift();

        console.log(`[ORCHESTRATOR] Dequeueing event ${task.eventName}`);
        // Re-publish the event to trigger its handler now
        bus.publish(task.eventName, task.payload);
        
        this.isProcessingQueue = false;
    }
}

export const orchestrator = new RuntimeOrchestrator();
