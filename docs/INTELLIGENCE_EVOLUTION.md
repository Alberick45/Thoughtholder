# JAOS Intelligence Evolution Plan: Phases 1–3

This document outlines the strategic roadmap for evolving JAOS from a reactive conversational assistant into an **Ambient Cognitive Runtime**.

---

## 🏗️ Phase 1: Environmental Awareness Foundation
**Goal:** Build the infrastructure that allows JAOS to "see" the user's digital and mental environment without being prompted.

### 1.1 Environmental Signal Aggregator (`EnvironmentalSignalAggregator.js`)
A background service that periodically scans the local database to extract high-level status signals.
- **Task Momentum**: Tracks the ratio of completed vs. new tasks over a 24-hour window.
- **Intent Drift**: Identifies tasks or purchase items that have been "Fresh" but untouched for more than 3 days.
- **Cognitive Density**: Measures the volume of thoughts/notes created in the last 4 hours to estimate current mental activity.

### 1.2 Data Ingestion Architecture
- **Passive Scanners**: Non-blocking database queries that run during "Sleep Cycles" or idle time.
- **Event Hooks**: Lightweight triggers that update awareness state when specific commands (like `/todo` or `/tobuy`) are used.

---

## 🧠 Phase 2: Contextual Memory & Life Modeling
**Goal:** Move beyond isolated chat logs to a unified model of the user's ongoing life structure.

### 2.1 Life Context Model (`LifeContextModel.js`)
A probabilistic model that maintains a "current state of reality."
- **Active Focus**: The project or topic that currently dominates the user's input.
- **Continuity Anchors**: Keywords that persist across multiple days (e.g., "Flutter", "Mommy's laptop").
- **Avoidance Patterns**: Identifying specific topics or task types that the user consistently ignores or moves to trash.

### 2.2 Memory Layers
- **Temporal Memory**: Understands the "Rhythm of the User" (e.g., morning is for study, evening is for chores).
- **Project Continuity**: A dedicated memory segment that remembers the "last known state" of a long-term project.

---

## 🎼 Phase 3: Ambient Cognitive Orchestration
**Goal:** Use the awareness and memory to provide subtle, proactive support.

### 3.1 Attention Management Engine
Determines *if* and *how* Jarvis should intervene.
- **Relevance Scoring**: Comparing an incoming event (like a deadline) against the current "Active Focus."
- **Cognitive Load Filter**: If the user is currently in a "High Density" thought session, Jarvis suppresses non-critical suggestions.

### 3.2 Selective Proactivity
- **Subtle Anchoring**: Instead of "You missed this," Jarvis says "I noticed some momentum on [Project X] earlier, keeping it in the loop."
- **Context Synthesis**: When the user asks a question, Jarvis automatically injects relevant ambient signals (e.g., "By the way, you still have [Item] on your buy list from yesterday").

---

## 📜 Behavioral Rules (The "Ambient" Oath)
1. **Help Quietly**: Never interrupt a flow state unless there is a critical system failure.
2. **Respect Silence**: Silence is not a lack of intelligence; it is a sign of respect for user agency.
3. **Preserve Agency**: Suggestions must always be framed as optional data points, never as commands.
4. **Probabilistic Belief**: Never claim absolute certainty about the user's state (e.g., use "It seems like..." instead of "You are...").
