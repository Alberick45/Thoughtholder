# Strategist Arsenal: Deep System Map (v5.0)

This map details the responsibility of every module in the Strategist Arsenal ecosystem, including the newly integrated Forensic, Personalization, and stabilized touch-optimized Mobile layers.

---

## 🎨 UI & Layout Layer (`src/app/layout/`)
- **`Header.jsx`**: Manages top-level navigation, branding, and encrypted JSON file imports.
- **`GlobalWidget.jsx`**: The "Tactical Hub." Hosts Jarvis Chat, the Calendar, and the OCR Vision dropzone. Now fully integrated with the `SettingsModal` portal on desktop and mobile.

## 🧠 Brain-Dump Layer (`src/features/brain-dump/`)
- **`InputBar.jsx`**: The command-line interface. Handles thought capture, hashtag parsing, and vault-access commands (e.g., `/vault`).
- **`ThoughtCard.jsx`**: The primary display unit. Handles linking, pinning, and status transitions (Archive/Trash). On mobile, now fully powered by `useLongPress` to bypass mouse right-clicks and summon security actions natively.

## 🦾 Intelligence Layer (`src/features/intelligence/`)
- **`engines/`**: **[JAOS COGNITIVE OPERATING SYSTEM]**
    - `CognitiveEventBus.js`: The central nervous system.
    - `RuntimeOrchestrator.js`: The task manager.
    - `CognitiveStateManager.js`: The "Pre-Frontal Cortex."
    - `ModelRouter.js`: Tiered inference gateway (Tier 1/2/3).
    - `ReactiveEngine.js`: Handles immediate dialogue.
    - `SleepEngine.js`: Background memory compression.
    - `ReflectiveEngine.js`: Post-session outcome analysis.
    - `RelationshipEngine.js`: Tracks relational depth and trust scores.
- **`identity/`**: **[IMMUTABLE CORE IDENTITY]**
    - `IdentityAuthority.js`: Source of truth for AI selfhood and Operator Identity sync.
    - `IdentityValidator.js`: Semantic Firewall against identity inversion.
- **`components/`**: **[ALIVE SYSTEM UX]**
    - `CognitiveDashboard.jsx`: Real-time engine monitoring.
    - `CognitiveStream.jsx`: UI monologue overlay.
    - `JarvisChat.jsx`: Primary AI interaction interface. Handles "Autonomous Query" conversational matrices.
- **`services/embeddings.js`**: Vector engine for semantic memory.

## 🔐 Vault & Forensic Layer (`src/features/vault/`)
- **`components/Arsenal.jsx`**: Level 4 UI. Handles dynamic Sub-Layer filtering and Payloads. On mobile, refactored with a responsive horizontal scroll tray and compact vertical action cards for touch-first efficiency.
- **`components/WineCellar.jsx`**: Level 2 Decoy UI. Completely redesigned for mobile devices, swapping mouse-driven setup triggers for native long-press combinations.
- **`components/VaultSetupUI.jsx`**: Authentication gatekeeper (Password/PIN/Picture).
- **`components/VaultRecovery.jsx`**: **[FORENSIC RECOVERY]** Scans for orphaned vaults and re-links triggers to orphaned encrypted data.
- **`services/credentialManager.js`**: Encrypted storage for external secrets.

## ⚙️ Shared & Personalization Layer (`src/shared/`)
- **`ui/SettingsModal.jsx`**: **[SYSTEM CONTROL PANEL]** Manages Operator Identity, Custom Hotkeys, Security Eradication, and Remote Jarvis IP (network-bridged Ollama sync).
- **`hooks/useLongPress.js`**: **[TOUCH GESTURE DETECTOR]** High-precision custom hook handling long-press inputs, ensuring complete compatibility with native capacitive screens.
- **`infrastructure/db.js`**: Dexie.js core. Includes the **Intelligent Merge** and **Attention Engine**.
- **`utils/normalization.js`**: **[SELF-HEALING ENGINE]** Enforces schemas and automatically repairs corrupted metadata (e.g., stringified arrays/blobs).
- **`utils/crypto.js`**: AES-GCM and PBKDF2 cryptographic primitives.

---

## 🛠️ Emergency Diagnostic Guide (Debugging)

If the system experiences anomalies, inspect the following files immediately:

| Issue | Target File | Logic to Inspect |
|---|---|---|
| **Vaults Disappearing** | `Arsenal.jsx` | `filteringLogic` - Ensure tags match `activeLayer`. |
| **Transfer Not Visible** | `App.jsx` | `onRelocate` - Check if the target layer exists in `allKnownLayers`. |
| **Auth Loops / Ghost PWD** | `App.jsx` | `isSubstantive` check in `openVaultUI`. |
| **Invisible Pictures** | `VaultSetupUI.jsx` | `useEffect` - Check `URL.createObjectURL` and `Blob` instance checks. |
| **Data Corruption** | `normalization.js` | `sanitizeObject` - Ensure `Array` and `Blob` types are preserved. |
| **Shortcuts Not Working** | `App.jsx` | `handleKeyDown` listener - Check `localStorage` key binding sync. |
| **Jarvis ID Mismatch** | `IdentityAuthority.js`| `getAuthorityState` - Verify kernel name sync. |
| **Gesture Failures (Mobile)** | `useLongPress.js`| `onTouchStart` / `onTouchEnd` callbacks and delay timer configuration. |

---

## 🔋 System Lifecycle (v5.0)
1. **Bootstrap**: `App.jsx` connects to `db.js`.
2. **Identity Sync**: `IdentityAuthority` pulls the Operator's name from the Jarvis kernel.
3. **OS Wakes**: Cognitive OS Engines initialize; `RuntimeOrchestrator` begins heartbeats.
4. **Command Binding**: `App.jsx` reads custom hotkeys from `localStorage` and binds them to the system listener.
5. **Forensic Scan**: The `useBackgroundDaemons` hook checks for metadata consistency.
6. **Reactive Interaction**: User engaged via `InputBar` or `Chat`.
7. **Secure Transition**: `/vault` or `Ctrl+Shift+V` triggers the Hydra transition logic in `App.jsx`.
8. **Self-Healing**: On data retrieval, `normalization.js` transparently repairs any metadata types corrupted during storage.
9. **Sleep**: Inactivity triggers the `SleepEngine` for database hygiene.
