# Strategist Arsenal: Enterprise Modular Architecture

This document serves as the official technical blueprint for the Strategist Arsenal (v4.0). The project has been refactored from a monolithic codebase into a **Feature-Based Modular Architecture** to ensure scalability, maintainability, and zero-trust security.

---

## 🏗️ 1. High-Level Architectural Layers

The system is organized into four distinct horizontal layers, each with a strict responsibility.

### 📍 Core Layer (`src/core/`)
The foundational "Source of Truth."
- **`config/constants.js`**: Centralized system settings (AI URLs, DB versioning, Security levels).
- **`types/index.js`**: Global object definitions and JSDoc schemas.
- **`security/`**: Protocols for the "Deep Guard" encryption engine.

### 📍 App Layer (`src/app/`)
The "Orchestrator" and UI skeleton.
- **`App.jsx`**: The main entry point. Now a "Headless Orchestrator" that manages top-level state and routing.
- **`hooks/`**: Universal logic shared across the app (e.g., `useBackgroundDaemons`, `useAutoBackup`).
- **`layout/`**: Global UI frames like the `Header` and the `GlobalWidget` hub.

### 📍 Feature Layer (`src/features/`)
Self-contained domain modules. Each folder contains its own components and specialized services.
- **`brain-dump/`**: The core data capture engine.
### 📍 Intelligence Layer (`src/features/intelligence/`)
The AI brain of the system, now refactored into a **Cognitive Operating System**.
- **`engines/`**: The core runtime. Uses a **Cognitive Event Bus** to decouple reasoning from the UI.
- **`ModelRouter.js`**: Tiered inference gateway. Optimizes hardware by routing background tasks to small models (Phi-3) and complex logic to large models (Qwen 14B).
- **`prompts/`**: Modular prompt generation based on 11 distinct cognitive states and evolving relational depth.
- **`services/embeddings.js`**: Manages vectorization of thoughts for semantic memory.

### 📍 Shared Layer (`src/shared/`)
Reusable infrastructure and cross-cutting utilities.
- **`infrastructure/db.js`**: The Dexie.js persistence engine.
- **`utils/crypto.js`**: Cryptographic primitives used by the Vault.
- **`ui/`**: Atomic UI components (Buttons, Panels) used by multiple features.

---

## 🔄 2. Data & Execution Flow

### The "Pulse" (Background Execution)
Background tasks are no longer inside the UI components.
1. `App.jsx` initializes the `useBackgroundDaemons` hook.
2. Every 10 minutes, the **Proactive Jarvis Daemon** scans the database for upcoming events.
3. Every 24 hours, the **Psychoanalysis Engine** calculates the user's psychological profile.
4. All intervals are automatically cleared when the app unmounts to prevent memory leaks.

### The "Deep Guard" (Security Pipeline)
1. User requests access to a secured layer (e.g., Level 4).
2. `App.jsx` routes to the `VaultSetupUI` component.
3. Input is compared against hashes stored in `db.settings`.
4. Upon verification, the `appLevel` state is updated, unlocking feature-gated components.

---

## 📂 3. Directory Map (Quick Reference)

```text
src/
├── app/
│   ├── hooks/          <-- Background intervals & Auto-backup
│   └── layout/         <-- Global Header & Widget Hub
├── core/
│   ├── config/         <-- SYSTEM_CONFIG & AI_CONFIG
│   └── types/          <-- Data schemas
├── features/
│   ├── brain-dump/     <-- InputBar & ThoughtCard
│   ├── intelligence/   <-- Jarvis Chat & OCR Logic
│   ├── vault/          <-- Encryption & Arsenal Components
│   └── visuals/        <-- Graph Maps & Calendars
├── shared/
│   ├── infrastructure/ <-- db.js (IndexedDB)
│   └── utils/          <-- crypto.js
└── App.jsx             # Clean Entry Point
```

---

## 🚀 4. Developer Rules & Scaling
- **Zero Inline Logic**: Move any logic exceeding 20 lines into a Service or Hook.
- **Unidirectional Imports**: Features should never import from other features. They must communicate through `shared/` or the `app/` state.
- **Constant Usage**: Never hardcode strings or URLs. Use `src/core/config/constants.js`.

---

## 🔨 5. Production Build Guide

The project supports **three deployment targets**: web browser, Electron desktop, and Android mobile.

### Prerequisites
Ensure the following are installed globally before building:
```bash
node --version   # Must be >= 18
npm --version    # Must be >= 9
```

### Step 1 — Install Dependencies
```bash
cd testwritingapp
npm install
```

### Step 2A — Web / Browser Build
Produces a static site in the `dist/` folder. Suitable for self-hosting or serving over localhost.
```bash
npm run build
npm run preview   # Test the production bundle locally at http://localhost:4173
```

### Step 2B — Desktop App Build (Electron + Ollama Embedded)
This is the **recommended production build**. It produces a fully self-contained installer that silently ships Ollama inside the binary.

#### Development mode (live-reload):
```bash
npm run electron:dev
```

#### Production installer:
```bash
# Windows (.exe / NSIS installer) → output: release/
npm run electron:build:win

# macOS (.dmg) → output: release/
npm run electron:build:mac

# Linux (.AppImage + .deb) → output: release/
npm run electron:build:linux
```

> **What happens during `electron:build`:**
> 1. `prebuild` runs `scripts/download-ollama.js` — this auto-downloads the correct Ollama binary for the current OS into `bin/`.
> 2. `vite build` compiles the React app into `dist/`.
> 3. `electron-builder` packages `dist/`, `electron/`, and `bin/` into a platform installer. The `bin/` folder is bundled as `extraResources` so Ollama ships inside the app.

### Step 2C — Android Mobile Build (Capacitor)
```bash
npm run build                   # Build web assets first
npx cap sync android            # Sync into the Android project
npx cap open android            # Open in Android Studio, then build/sign from there
```

> **Note:** The mobile build runs in a browser context — Ollama is **not** available on mobile. Jarvis will show as offline unless you point `AI_CONFIG.OLLAMA_BASE_URL` to a remote inference server.

---

## 🤖 6. Ollama Embedding Architecture

The desktop build ships Ollama as a **silent background daemon** that starts automatically with the app. No separate installation is required for end users.

### How It Works

```
Electron Main Process (electron/main.js)
│
├── app.whenReady()
│   ├── startOllama()          ← Spawns: bin/ollama.exe serve
│   └── createWindow()         ← Loads dist/index.html
│
└── app.on('before-quit')
    └── ollamaProcess.kill()   ← Clean shutdown of the daemon
```

### Binary Resolution — `getOllamaPath()`
The main process uses environment-aware path resolution:
| Context | Binary Location |
|---|---|
| Dev (`npm run electron:dev`) | `./bin/ollama.exe` |
| Packaged installer | `process.resourcesPath/bin/ollama.exe` |
| Fallback (Ollama already installed globally) | System `PATH` |

### Downloading the Binary — `scripts/download-ollama.js`
Run automatically before every build via the `prebuild` npm hook.
- **Windows**: Downloads `ollama-windows-amd64.zip` from GitHub Releases → extracts to `bin/`.
- **macOS**: Downloads `ollama-darwin` raw binary → sets `chmod 755`.
- **Linux**: Downloads `ollama-linux-amd64` raw binary → sets `chmod 755`.
- **Skip logic**: If `bin/ollama.exe` already exists, the download is skipped (CI-friendly).

### Pulling a Model After First Launch
After the app starts, Ollama runs but has no models loaded. The first time a user interacts with Jarvis, a model pull is triggered via IPC:

```javascript
// In JarvisChat.jsx — model selector dropdown
await window.electronAPI.runModel('llama3');
// Electron main.js handles: spawn(ollamaPath, ['run', modelName])
```

Recommended models and their VRAM requirements:
| Model | Size | Min VRAM | Use Case |
|---|---|---|---|
| `phi3` | 3.8B | 4 GB | Fast reactive chat (Tier 1) |
| `llama3` | 8B | 8 GB | Standard dialogue (Tier 2) |
| `qwen:14b` | 14B | 16 GB | Deep analysis tasks (Tier 3) |

### Changing the Inference URL
If using a remote Ollama server instead of the bundled one, update `src/core/config/constants.js`:
```javascript
export const AI_CONFIG = {
  OLLAMA_BASE_URL: 'http://YOUR_SERVER_IP:11434',  // ← change this
  DEFAULT_MODEL: 'llama3',
};
```
npm run electron:build