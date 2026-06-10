/**
 * JAOS Relationship Engine
 * Manages the persistent, evolving relational depth between the AI and the user.
 * Implements trust tracking, interaction quality scoring, and behavioral adaptation.
 */

import { bus } from './CognitiveEventBus';
import { db } from '../../../shared/infrastructure/db';

export class RelationshipEngine {
    constructor() {
        this.initializeSubscribers();
        // Force evaluation on boot to clear stale legacy states
        setTimeout(() => this.evaluateRelationalState(), 1000);
    }

    initializeSubscribers() {
        // Trigger evaluation periodically or after significant sessions
        bus.subscribe('TASK_COMPLETE', async (data) => {
            if (data?.type === 'DEEP_FOCUS' || data?.type === 'REACTIVE') {
                await this.evaluateRelationalState();
            }
        });

        // Trigger decay checks during sleep/maintenance
        bus.subscribe('START_MEMORY_COMPRESSION', async () => {
            await this.applyRelationalDecay();
        });
    }

    /**
     * Calculates interaction quality based on the last session
     */
    async scoreInteractionQuality(sessionLogs) {
        // Simple heuristic: length of session, complexity of words, emotional tags
        const totalLength = sessionLogs.reduce((acc, log) => acc + log.content.length, 0);
        let qualityScore = 1.0;
        
        if (totalLength > 2000) qualityScore += 0.5; // Deep Technical Session
        if (sessionLogs.some(l => l.content.includes('[EMOTION:'))) qualityScore += 0.3; // Emotional Support
        
        return qualityScore;
    }

    async evaluateRelationalState() {
        const { calculateEvolutionState } = await import('../evolution/personalityEvolution');
        const currentStateStr = localStorage.getItem('jaos_evolution_state');
        const oldState = currentStateStr ? JSON.parse(currentStateStr) : { depth: 'STRANGER' };

        const newState = await calculateEvolutionState();

        if (oldState.depth !== newState.depth) {
            console.log(`[RELATIONSHIP_ENGINE] Evolution shift: ${oldState.depth} -> ${newState.depth}`);
            localStorage.setItem('jaos_evolution_state', JSON.stringify(newState));
            
            bus.publish('RELATIONSHIP_SHIFT', {
                previous: oldState.depth,
                current: newState.depth,
                score: newState.relationalScore
            });
        }
    }

    async applyRelationalDecay() {
        const { calculateEvolutionState } = await import('../evolution/personalityEvolution');
        const state = await calculateEvolutionState();
        
        if (state.axes.decayFactor < 1.0) {
            console.log(`[RELATIONSHIP_ENGINE] Applying atrophy. Decay factor: ${state.axes.decayFactor}`);
            bus.publish('RELATIONAL_ATROPHY', state.axes.decayFactor);
        }
    }
}

export const relationshipEngine = new RelationshipEngine();
