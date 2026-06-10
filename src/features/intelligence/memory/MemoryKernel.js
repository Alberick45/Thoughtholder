/**
 * JAOS Phase 4: Structured Memory Kernel
 * Responsibility: Managing the lifecycle of structured facts and episodic memory.
 * Replaces raw text dumps with structured intelligence.
 */

import { db } from '../../../shared/infrastructure/db';

export class MemoryKernel {
    /**
     * Retrieves the most relevant structured facts for a given query.
     */
    async getStructuredContext(query) {
        console.log("[MEMORY_KERNEL] Retrieving context for:", query);
        
        try {
            // 1. Fetch User Profile (Facts)
            const facts = await db.thoughts
                .where('type').anyOf('profile_fact', 'preference')
                .toArray();

            // 2. Fetch Recent Episodic Context (Summaries)
            const episodes = await db.thoughts
                .filter(t => t.type === 'conversation_summary')
                .limit(3)
                .toArray();

            // 3. Format into Clean Blocks (Phase 4 Requirement)
            const profile = facts.reduce((acc, f) => {
                acc[f.key] = f.value;
                return acc;
            }, {});

            const contextBlocks = [];
            
            if (Object.keys(profile).length > 0) {
                let profileStr = "[USER PROFILE]\n";
                for (const [key, val] of Object.entries(profile)) {
                    profileStr += `${key}: ${val}\n`;
                }
                contextBlocks.push(profileStr.trim());
            }

            if (episodes.length > 0) {
                let historyStr = "[RECENT CONTEXT]\n";
                historyStr += episodes.map(e => `- ${e.content}`).join('\n');
                contextBlocks.push(historyStr.trim());
            }

            return contextBlocks.join('\n\n');
        } catch (error) {
            console.error("[MEMORY_KERNEL] Retrieval Error:", error);
            return "";
        }
    }

    /**
     * Ingests raw text to extract and store new facts.
     */
    async ingest(text, role = 'user') {
        if (role !== 'user') return; // For now, only learn from user input

        // Simple Rule-based Extraction (Phase 4.1)
        // "hi im albert" -> name: Albert
        const nameMatch = text.match(/i(?:'|a)?m\s+([A-Z][a-z]+)/i);
        if (nameMatch) {
            const name = nameMatch[1];
            await this.storeFact('name', name, 0.95);
        }

        // "i like software architecture" -> interest: software architecture
        const interestMatch = text.match(/i\s+(?:like|love|interest(?:ed)? in)\s+([\w\s]+)/i);
        if (interestMatch) {
            const interest = interestMatch[1].trim();
            await this.storeFact('interest', interest, 0.8);
        }
    }

    async storeFact(key, value, confidence = 1.0) {
        console.log(`[MEMORY_KERNEL] Learning fact: ${key} = ${value}`);
        
        // Upsert logic: find existing fact with this key
        const existing = await db.thoughts.where('key').equals(key).first();
        
        const factData = {
            id: existing?.id || crypto.randomUUID(),
            type: 'profile_fact',
            thought_id: `Fact-${key}`,
            content: `**[Structured Memory]** ${key}: ${value}`,
            tags: ['memory-fact', 'jarvis-verified'],
            key,
            value,
            confidence,
            created_at: Date.now(),
            updated_at: Date.now(),
            status: 'active'
        };

        if (existing) {
            await db.thoughts.update(existing.id, factData);
        } else {
            await db.thoughts.add(factData);
        }
    }
}

export const memoryKernel = new MemoryKernel();
