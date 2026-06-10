/**
 * JAOS Reactive Engine
 * Handles immediate user requests and orchestrates the primary response loop.
 */

import { bus } from './CognitiveEventBus';
import { db } from '../../../shared/infrastructure/db';

export class ReactiveEngine {
    constructor() {
        this.isProcessing = false;
    }

    async process(query) {
        if (this.isProcessing) return;
        this.isProcessing = true;

        bus.publish('COGNITIVE_ACTIVITY', { type: 'REACTIVE', status: 'STARTING' });

        try {
            console.log("[REACTIVE_ENGINE] Starting process for query:", query);
            
            // --- PHASE 3: INTENT ANALYSIS (PRE-COGNITIVE) ---
            const { MessageIntentEngine, INTENTS } = await import('./MessageIntentEngine');
            const intent = MessageIntentEngine.classify(query);
            console.log("[REACTIVE_ENGINE] Detected Intent:", intent);

            const { identityAuthority } = await import('../identity/IdentityAuthority');
            const authorityState = await identityAuthority.getAuthorityState();
            const userName = authorityState.user.preferred_name || 'User';

            // PHASE 1.5 & 4: SYSTEM AWARENESS BYPASS (Grounding Layer)
            if (intent === INTENTS.TASK_QUERY) {
                console.log("[REACTIVE_ENGINE] Fast-tracking task query.");
                const { TaskEngine } = await import('./TaskEngine');
                const reply = await TaskEngine.getTaskSummary();
                return { reply };
            }

            // PHASE 1.5: Greeting & Identity Bypass (Lightweight Mode)
            if ((intent === INTENTS.GREETING || intent === INTENTS.IDENTITY_QUERY) && query.length < 30) {
                console.log("[REACTIVE_ENGINE] Fast-tracking lightweight response.");
                const reply = MessageIntentEngine.getGreetingResponse(userName, query);
                return { reply };
            }

            // --- LAYER 1: DATA RETRIEVAL & GROUNDING ---
            console.log("[REACTIVE_ENGINE] Layer 1: Data Retrieval...");
            const thoughts = await db.thoughts.where('status').notEqual('archived').limit(50).toArray();
            
            // --- LAYER 2: COGNITIVE STATE CONSTRUCTION ---
            console.log("[REACTIVE_ENGINE] Layer 2: Cognitive State...");
            const { ThoughtAnalyzer } = await import('../runtime/ThoughtAnalyzer');
            const analyzed = ThoughtAnalyzer.analyzeBatch(thoughts);

            const { CognitiveStateEngine } = await import('../runtime/CognitiveStateEngine');
            const awarenessStore = await db.settings.get('jaos_awareness_state');
            const awareness = awarenessStore?.value || {};
            const cognitiveState = CognitiveStateEngine.construct(analyzed, awareness);

            // --- LAYER 4: ENVIRONMENT SNAPSHOT ---
            console.log("[REACTIVE_ENGINE] Layer 4: Snapshot Builder...");
            const { SnapshotBuilder } = await import('../runtime/SnapshotBuilder');
            const snapshot = SnapshotBuilder.build(cognitiveState, [], { focus: awareness.focus });

            // --- LAYER 5: MEMORY RECONSTRUCTION (PHASE 5 PREP) ---
            console.log("[REACTIVE_ENGINE] Layer 5: Memory Isolation...");
            const { getCognitiveContext } = await import('../memory/memoryRetriever');
            const context = await getCognitiveContext(query);
            
            // Context Isolation: Convert objects to clean, separated text blocks
            const workingText = (context.working || []).map(t => `- ${t.content || t.value}`).join('\n');
            const focusText = (context.focus || []).map(t => `! ${t.content || t.value}`).join('\n');

            // --- LAYER 6: AI INFERENCE (PHASE 1 SECURE PROMPT) ---
            console.log("[REACTIVE_ENGINE] Layer 6: AI Inference...");
            const { buildSystemPrompt } = await import('../prompts/buildSystemPrompt');
            const { runReflectionLoop } = await import('../reasoning/reflectionLoop');
            const { ConversationGovernanceEngine } = await import('./ConversationGovernanceEngine');
            
            bus.publish('MODEL_THINKING', { step: 'REFLECTING', message: 'Analyzing strategic alignment...' });
            const reflection = await runReflectionLoop({ momentum: context.momentum });
            
            // Inject Governance Layer into Prompt
            const governancePrompt = ConversationGovernanceEngine.getGovernanceDirectives();
            const systemPrompt = buildSystemPrompt(authorityState, snapshot, reflection) + "\n\n" + governancePrompt;

            const { ModelRouter, ModelTiers } = await import('./ModelRouter');
            const router = new ModelRouter();
            
            const messages = [
                { role: 'system', content: systemPrompt },
                { role: 'user', content: `[BACKGROUND_CONTEXT]:\n${focusText}\n${workingText}\n\n[USER_INPUT]:\n${query}` }
            ];

            let reply = await router.route(messages, { 
                tier: ModelTiers.TIER_2_DIALOGUE,
                maxTokens: 1000 
            });

            // --- PHASE 1 & 2: POST-INFERENCE SANITIZATION & GOVERNANCE ---
            const { CognitiveSanitizer } = await import('../services/CognitiveSanitizer');
            const cleanReply = CognitiveSanitizer.distill(reply);
            
            // --- RESPONSE CONFIDENCE LIMITER (PHASE 1.5) ---
            let governedReply = ConversationGovernanceEngine.govern(query, cleanReply, intent);
            if (governedReply.length > 500 && intent === INTENTS.CASUAL) {
                console.warn("[GOVERNANCE] Confidence Limiter triggered: Excessive verbosity in casual chat. Compressing.");
                governedReply = governedReply.split(/[.!?]\s/).slice(0, 3).join('. ') + '.';
            }

            console.log("[REACTIVE_ENGINE] Process complete.");
            return { systemPrompt, reflection, reply: governedReply };

        } catch (error) {
            console.error("[REACTIVE_ENGINE] Processing failed:", error);
            bus.publish('COGNITIVE_ERROR', error.message);
            return { reply: "System kernel disruption. Error: " + error.message };
        } finally {
            this.isProcessing = false;
            bus.publish('COGNITIVE_ACTIVITY', { type: 'REACTIVE', status: 'IDLE' });
        }
    }
}
