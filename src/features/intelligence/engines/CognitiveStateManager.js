/**
 * JAOS Cognitive State Manager
 * The deterministic State Machine for the Cognitive Operating System.
 * Manages runtime states, priority scheduling, and model load balancing.
 */

import { bus } from './CognitiveEventBus';

export const CognitiveStates = {
    IDLE_MONITORING: 'IDLE_MONITORING',
    REACTIVE: 'REACTIVE',
    PROACTIVE: 'PROACTIVE',
    DEEP_FOCUS: 'DEEP_FOCUS',
    OBSERVATION: 'OBSERVATION',
    REFLECTIVE: 'REFLECTIVE',
    EMOTIONAL_PROCESSING: 'EMOTIONAL_PROCESSING',
    SOCIAL: 'SOCIAL',
    MAINTENANCE: 'MAINTENANCE',
    SLEEP: 'SLEEP',
    EMERGENCY_OVERRIDE: 'EMERGENCY_OVERRIDE'
};

export class CognitiveStateManager {
    constructor() {
        this.currentState = CognitiveStates.IDLE_MONITORING;
        this.lastState = null;
        this.stateHistory = [];
        this.priorityLocks = new Set();
        
        this.registerEventHandlers();
    }

    /**
     * State Definitions & Transition Rules
     */
    getStateConfig(state) {
        const configs = {
            [CognitiveStates.IDLE_MONITORING]: {
                priority: 1,
                modelUsage: 'Ambient (Tier 1)',
                intensity: 'Low',
                uiIndicator: 'Dimmed Pulse',
                description: 'Passive listening for events. Minimal resource drain.'
            },
            [CognitiveStates.REACTIVE]: {
                priority: 8,
                modelUsage: 'Main (Tier 2)',
                intensity: 'High',
                uiIndicator: 'Solid Glow',
                description: 'Directly fulfilling a user request.'
            },
            [CognitiveStates.DEEP_FOCUS]: {
                priority: 9,
                modelUsage: 'Large (Tier 3)',
                intensity: 'Max',
                uiIndicator: 'Intense Blue Stream',
                description: 'Heavy computational tasks (e.g., code analysis, complex planning).'
            },
            [CognitiveStates.MAINTENANCE]: {
                priority: 2,
                modelUsage: 'None/Tier 1',
                intensity: 'Low',
                uiIndicator: 'Subtle Orange Pulse',
                description: 'Database cleanup, vector consolidation.'
            },
            [CognitiveStates.EMOTIONAL_PROCESSING]: {
                priority: 6,
                modelUsage: 'Ambient (Tier 1)',
                intensity: 'Medium',
                uiIndicator: 'Soft Purple Shift',
                description: 'Analyzing recent relational or emotional shifts.'
            },
            [CognitiveStates.SLEEP]: {
                priority: 0,
                modelUsage: 'None',
                intensity: 'Zero',
                uiIndicator: 'Off',
                description: 'Memory compression and system rest.'
            }
        };
        return configs[state] || configs[CognitiveStates.IDLE_MONITORING];
    }

    registerEventHandlers() {
        bus.subscribe('USER_INPUT', () => this.transitionTo(CognitiveStates.REACTIVE, 'User initiated interaction.'));
        bus.subscribe('COMPLEX_TASK_DETECTED', () => this.transitionTo(CognitiveStates.DEEP_FOCUS, 'High cognitive load requested.'));
        bus.subscribe('EMOTIONAL_SHIFT', () => this.transitionTo(CognitiveStates.EMOTIONAL_PROCESSING, 'Significant emotional change detected.'));
        bus.subscribe('LONG_INACTIVITY', () => this.transitionTo(CognitiveStates.MAINTENANCE, 'Idle timeout reached.'));
        bus.subscribe('TASK_COMPLETE', () => this.transitionTo(CognitiveStates.IDLE_MONITORING, 'Execution finished.'));
    }

    /**
     * Priority-based State Transition Logic
     */
    transitionTo(newState, reason) {
        if (this.currentState === newState) return;

        const currentConfig = this.getStateConfig(this.currentState);
        const newConfig = this.getStateConfig(newState);

        // Priority Conflict Resolution
        if (currentConfig.priority > newConfig.priority && !this.canInterrupt(this.currentState)) {
            console.log(`[STATE_MANAGER] Blocked transition to ${newState}: ${this.currentState} has higher priority.`);
            return false;
        }

        // Commit Transition
        this.lastState = this.currentState;
        this.currentState = newState;
        this.stateHistory.push({ state: newState, timestamp: Date.now(), reason });
        
        // Broadcast shift
        bus.publish('STATE_CHANGED', { 
            previous: this.lastState, 
            current: this.currentState,
            config: newConfig,
            reason 
        });

        console.log(`[STATE_MANAGER] Transition: ${this.lastState} -> ${this.currentState} (${reason})`);
        return true;
    }

    canInterrupt(state) {
        // Deep Focus and Reactive states are generally uninterruptible unless by Emergency.
        return ![CognitiveStates.DEEP_FOCUS, CognitiveStates.EMERGENCY_OVERRIDE].includes(state);
    }
}

export const stateManager = new CognitiveStateManager();
