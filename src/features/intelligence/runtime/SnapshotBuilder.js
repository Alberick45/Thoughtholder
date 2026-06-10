/**
 * LAYER 4 — ENVIRONMENT SNAPSHOT BUILDER (HARDENED)
 * Responsibility: Construct a compressed AI-readable reality layer.
 *
 * RULE: Only STRING-safe primitives leave this layer.
 */

import { safeStringify, normalizeValue } from '../../../shared/utils/normalization';

export class SnapshotBuilder {

    // -------------------------
    // MAIN ENTRY
    // -------------------------
    static build(cognitiveState, events = [], appState = {}) {

        const snapshot = {
            tasks: (cognitiveState.pending_tasks || [])
                .map(t => normalizeValue(t)),

            buy_list: (cognitiveState.buy_list || [])
                .map(b => normalizeValue(b)),

            active_projects: (cognitiveState.active_projects || [])
                .map(p => normalizeValue(p)),

            upcoming_events: (events || []).map(e => ({
                title: normalizeValue(e?.title),
                time: normalizeValue(e?.start)
            })),

            current_focus: appState?.focus
                ? normalizeValue(appState.focus)
                : "general",

            system_pressure: {
                tasks: Number(cognitiveState?.urgency_map?.task_pressure || 0),
                buy: Number(cognitiveState?.urgency_map?.procurement_pressure || 0)
            },

            timestamp: Date.now()
        };

        return this.serializeForAI(snapshot);
    }

    // -------------------------
    // FINAL SERIALIZATION LAYER
    // -------------------------
    static serializeForAI(snapshot) {

        const tasks = snapshot.tasks.filter(Boolean);
        const buys = snapshot.buy_list.filter(Boolean);
        const projects = snapshot.active_projects.filter(Boolean);
        const events = snapshot.upcoming_events || [];

        let report = "[ENVIRONMENT SNAPSHOT]\n";

        // TASKS
        report += tasks.length
            ? `TASKS: ${tasks.join(', ')}\n`
            : "TASKS: Clear.\n";

        // PURCHASES
        if (buys.length) {
            report += `PURCHASES: ${buys.join(', ')}\n`;
        }

        // PROJECTS
        if (projects.length) {
            report += `PROJECTS: ${projects.join(', ')}\n`;
        }

        // CALENDAR
        if (events.length) {
            report += `CALENDAR: ${events
                .map(e => `${e.title} at ${e.time}`)
                .join('; ')}\n`;
        }

        // FOCUS
        report += `FOCUS: ${snapshot.current_focus}\n`;

        // PRESSURE (SAFE GUARDS)
        const taskPressure = isNaN(snapshot.system_pressure.tasks)
            ? 0
            : snapshot.system_pressure.tasks;

        const buyPressure = isNaN(snapshot.system_pressure.buy)
            ? 0
            : snapshot.system_pressure.buy;

        report += `PRESSURE: Tasks: ${taskPressure.toFixed(2)}, Buy: ${buyPressure.toFixed(2)}\n`;

        report += `TIMESTAMP: ${snapshot.timestamp}\n`;

        return report;
    }
}