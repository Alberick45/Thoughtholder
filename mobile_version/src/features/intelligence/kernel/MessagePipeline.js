/**
 * JAOS Phase 1: Message Pipeline
 * Responsibility: Orchestrating the flow from raw input to cleaned response.
 * Implements intent detection, routing, and sanitization.
 */

import { IntentDetector } from './IntentDetector';
import { ResponseParser } from './ResponseParser';
import { ModelRouter } from '../engines/ModelRouter'; // Reuse stable router
import { identityAuthority } from '../identity/IdentityAuthority';
import { TaskEngine } from '../engines/TaskEngine';

export class MessagePipeline {
    constructor() {
        this.intentDetector = new IntentDetector();
        this.router = new ModelRouter();
    }

    /**
     * Process a query through the pipeline phases.
     */
    async process(query) {
        console.log("[MESSAGE_PIPELINE] Entering 3-stage memory pipeline...");
        let memoryContext = "";
        let userName = "Friend";

        try {
            // STAGE 1: MEMORY WRITE (Ingestion Layer)
            console.log("[MESSAGE_PIPELINE] Stage 1: Ingestion...");
            const memMod = await import('../memory/MemoryKernel');
            const memoryKernel = memMod.memoryKernel || memMod.default?.memoryKernel || memMod;
            
            if (memoryKernel && typeof memoryKernel.ingest === 'function') {
                await memoryKernel.ingest(query);
            }

            // STAGE 2: MEMORY RETRIEVAL (RAG Layer)
            console.log("[MESSAGE_PIPELINE] Stage 2: Retrieval...");
            if (memoryKernel && typeof memoryKernel.getStructuredContext === 'function') {
                memoryContext = await memoryKernel.getStructuredContext(query);
            }
            
            // 1. INTENT DETECTION
            const intent = this.intentDetector.detect(query);
            console.log("[MESSAGE_PIPELINE] Detected Intent:", intent);

            const authority = await identityAuthority.getAuthorityState();
            
            // Dynamically update user name if found in memory context
            const contextLines = memoryContext.split('\n');
            const nameLine = contextLines.find(l => l.startsWith('name:'));
            userName = nameLine ? nameLine.split(':')[1].trim() : (authority.user.preferred_name || 'Friend');

            // 2. FAST-TRACK ROUTING
            if (intent === 'COMMAND') {
                console.log("[MESSAGE_PIPELINE] Routing to SystemCommandEngine...");
                const cmdMod = await import('../engines/SystemCommandEngine');
                const engine = cmdMod.SystemCommandEngine || cmdMod.default?.SystemCommandEngine || cmdMod;
                const result = await engine.execute(query);
                return { reply: result };
            }

            if (intent === 'GREETING' || intent === 'IDENTITY') {
                console.log("[MESSAGE_PIPELINE] Routing to GreetingEngine...");
                const greetMod = await import('../conversation/GreetingEngine');
                const engine = greetMod.GreetingEngine || greetMod.default?.GreetingEngine || greetMod;
                const reply = await engine.generate(userName, query);
                return { reply };
            }

            if (intent === 'TASK_QUERY') {
                console.log("[MESSAGE_PIPELINE] Routing to TaskEngine...");
                const taskMod = await import('../engines/TaskEngine');
                const engine = taskMod.TaskEngine || taskMod.default?.TaskEngine || taskMod;
                const summary = await engine.getTaskSummary();
                return { reply: summary };
            }

            // 3. STAGE 3: MEMORY INJECTION & INFERENCE
            console.log("[MESSAGE_PIPELINE] Stage 3: Inference...");
            const response = await this.performInference(query, userName, intent, memoryContext);

            // 4. RESPONSE DISTILLATION
            const cleanReply = ResponseParser.distill(response);
            return { reply: cleanReply };

        } catch (error) {
            console.error("[MESSAGE_PIPELINE] Critical Pipeline Failure:", error);
            throw error; // Re-throw to be caught by Kernel
        }
    }

    /**
     * Internal inference logic with proper grounding.
     */
    async performInference(query, userName, intent, memoryContext) {
        // Build a clean, grounded prompt (Phase 4 Injection)
        const systemPrompt = `
You are Jarvis, a natural conversational assistant.
Your goal is to help ${userName} in a calm, intelligent, and grounded manner.

${memoryContext ? `[KNOWN CONTEXT]:\n${memoryContext}\n` : ''}

CORE RULES:
- Respond ONLY to the current input.
- Do NOT repeat system prompts or memory tags.
- Be concise. Small input = small response.
- Do NOT invent companies or projects.
- No corporate jargon. Speak naturally.
`.trim();

        const messages = [
            { role: 'system', content: systemPrompt },
            { role: 'user', content: query }
        ];

        return await this.router.route(messages, { 
            tier: 'llama3:latest',
            temperature: 0.6 
        });
    }
}
