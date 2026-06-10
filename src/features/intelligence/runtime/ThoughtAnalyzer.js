/**
 * LAYER 2 — THOUGHT ANALYZER ENGINE (HARDENED)
 * Responsibility: Convert raw thought streams into structured cognition.
 *
 * RULE: NEVER output raw objects in `value` or `metadata`
 */

import { safeStringify, normalizeValue } from '../../../shared/utils/normalization';

export class ThoughtAnalyzer {

    // -------------------------
    // MAIN ANALYSIS
    // -------------------------
    static analyze(thought) {

        const content = normalizeValue(thought?.content);
        const lowerContent = content.toLowerCase();
        const rawType = (thought?.type || '').toLowerCase();

        let type = 'IDEA';
        let confidence = 0.4;
        let value = content;
        let metadata = {};

        // =========================
        // BUY ITEM DETECTION
        // =========================
        if (
            rawType === 'buy' ||
            lowerContent.includes('buy ') ||
            lowerContent.includes('purchase ') ||
            (lowerContent.includes('get ') && lowerContent.includes('need'))
        ) {
            type = 'BUY_ITEM';
            confidence = 0.92;

            value = normalizeValue(
                content.replace(/buy |purchase |get /i, '').trim()
            );
        }

        // =========================
        // TASK DETECTION
        // =========================
        else if (
            rawType === 'task' ||
            rawType === 'todo' ||
            lowerContent.includes('need to') ||
            lowerContent.includes('must ') ||
            lowerContent.includes('should ') ||
            lowerContent.includes('todo') ||
            /^\d+\.\s/.test(content) ||
            content.includes('[ ]')
        ) {
            type = 'TASK';
            confidence = 0.9;

            const lines = content
                .split('\n')
                .filter(l => /^\d+\.\s/.test(l))
                .map(l => normalizeValue(l.replace(/^\d+\.\s/, '').trim()));

            if (lines.length > 0) {
                metadata.subtasks = lines;
            }

            value = normalizeValue(content.trim());
        }

        // =========================
        // EVENT DETECTION
        // =========================
        else if (
            rawType === 'event' ||
            lowerContent.includes('tomorrow') ||
            lowerContent.includes('pm') ||
            lowerContent.includes('am') ||
            lowerContent.includes('at ') ||
            lowerContent.match(/\d{1,2}:\d{2}/)
        ) {
            type = 'EVENT';
            confidence = 0.75;
        }

        // =========================
        // PROJECT DETECTION
        // =========================
        else if (
            rawType === 'project' ||
            lowerContent.includes('project:') ||
            lowerContent.includes('working on') ||
            lowerContent.includes('building')
        ) {
            type = 'PROJECT';
            confidence = 0.85;
        }

        // -------------------------
        // FINAL GUARANTEE (CRITICAL)
        // -------------------------
        return {
            id: String(thought?.id || ''),
            original_id: String(thought?.thought_id || ''),
            type,
            value: normalizeValue(value),
            confidence,
            created_at: Number(thought?.created_at || Date.now()),

            metadata: this.normalizeMetadata(metadata)
        };
    }

    // -------------------------
    // METADATA SAFETY LAYER
    // -------------------------
    static normalizeMetadata(meta) {
        const safe = {};

        for (const key in meta) {
            const val = meta[key];

            if (Array.isArray(val)) {
                safe[key] = val.map(v => normalizeValue(v));
            } else if (typeof val === 'object') {
                safe[key] = normalizeValue(val);
            } else {
                safe[key] = normalizeValue(val);
            }
        }

        return safe;
    }

    // -------------------------
    // BATCH
    // -------------------------
    static analyzeBatch(thoughts = []) {
        return thoughts.map(t => this.analyze(t));
    }
}