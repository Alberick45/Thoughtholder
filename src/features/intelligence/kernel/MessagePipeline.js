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

        // STAGE 1: MEMORY WRITE (Ingestion Layer)
        const { memoryKernel } = await import('../memory/MemoryKernel');
        await memoryKernel.ingest(query);

        // STAGE 2: MEMORY RETRIEVAL (RAG Layer)
        const memoryContext = await memoryKernel.getStructuredContext(query);
        
        // 1. INTENT DETECTION
        const intent = this.intentDetector.detect(query);
        console.log("[MESSAGE_PIPELINE] Detected Intent:", intent);

        const authority = await identityAuthority.getAuthorityState();
        
        // Dynamically update user name if found in memory context
        const contextLines = memoryContext.split('\n');
        const nameLine = contextLines.find(l => l.startsWith('name:'));
        const userName = nameLine ? nameLine.split(':')[1].trim() : (authority.user.preferred_name || 'Friend');

        // 2. FAST-TRACK ROUTING
        if (intent === 'COMMAND') {
            console.log("[MESSAGE_PIPELINE] Routing to SystemCommandEngine...");
            const { SystemCommandEngine } = await import('../engines/SystemCommandEngine');
            const result = await SystemCommandEngine.execute(query);
            console.log("[MESSAGE_PIPELINE] Command Execution Result:", result);
            return { reply: result };
        }

        if (intent === 'GREETING' || intent === 'IDENTITY') {
            const { GreetingEngine } = await import('../conversation/GreetingEngine');
            return { reply: GreetingEngine.generate(userName, query) };
        }

        if (intent === 'TASK_QUERY') {
            const summary = await TaskEngine.getTaskSummary();
            return { reply: summary };
        }

        // 3. STAGE 3: MEMORY INJECTION & INFERENCE
        const response = await this.performInference(query, userName, intent, memoryContext);

        // 4. RESPONSE DISTILLATION
        const cleanReply = ResponseParser.distill(response);

        return { reply: cleanReply };
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
