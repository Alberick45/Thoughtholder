# ThoughtHolder Friend's Guide (v6.0)

Welcome to ThoughtHolder, an ultra-private, AI-driven operating system designed to sit flawlessly over your internal hardware while aggressively shielding your thoughts, task management, and private encrypted vaults from cloud inspection.

This guide covers all basic, advanced, and native mobile functionality.

---

## 🧭 The Surface Dashboard

Upon launching the application, you enter the **Surface Layout (Level 1)**. This is your primary hub for normal tracking and productivity operations.

### Navigation and Commands
At the bottom of the interface, you will see your primary **Command Input Bar**. This operates entirely on `/` slashes. 

- **Basic Node Entry:** Simply type standard text and press Enter. It registers as a distinct memory/thought.
- **`/task`:** Generates a highly visible checkbox entry explicitly flagged for attention.
- **`/vault`:** Implements the core mechanism to traverse down into secure depths (See *The Wine Cellar Strategy*).
- **`/settings`**: Opens the Global Control Panel (Shortcut: `Ctrl + Shift + I`).

### 🏷️ Input Mode Toggles & Auto-Numbering
Directly below the text input, three stylized mode pill buttons allow you to switch the capture intent on the fly:
*   💭 **Thought Mode (Default)**: Normal chronological capture of fleeting ideas.
*   ✅ **Todo Mode**: Automatically prepares your input with auto-numbering. Hits the `/todo` command endpoint on submit.
*   🛒 **To Buy Mode**: Automatically prepares list numbering. Hits the `/tobuy` command endpoint on submit.
*   **Auto-Numbering Shortcut**: In *Todo* or *To Buy* modes, pressing `Shift + Enter` inside the input bar automatically inserts the next line number (e.g., `2. `) for swift multi-line list compilation.

### 🎙️ Offline-First Voice Input & Local WASM Fallback
The microphone button (`🎤`) enables rapid voice capture:
*   **Online Path (Native SpeechRecognition)**: When connected to the internet, native browser speech recognition streams text in real-time as you speak.
*   **Offline Path (Local WASM Whisper Engine)**: When disconnected from the internet, the system automatically falls back to secure, local audio processing:
    1. Captures local mic input using the browser's native `MediaRecorder`.
    2. Decodes and resamples the audio binary data to a high-quality **16kHz Float32Array** using standard `AudioContext`.
    3. Feeds the resampled audio into an embedded **Xenova/whisper-tiny.en** pipeline running entirely on device via WASM.
    4. Shows a dedicated pulsing status bar showing local transcription activity: `Offline Mode: Recording locally to WASM Whisper Engine...`.
*   **Silent Background Pre-Warming**: When the app starts up online, it prefetches and caches the lightweight 75MB Whisper model files. A beautiful glassmorphic progress bar shows the caching progress. Once cached, the offline voice engine is available completely offline!

### 📎 File & Picture Attachments
The paperclip icon (`📎`) lets you enrich your thoughts with visual assets and documents offline:
*   **Visual Assets**: Attach pictures directly from your machine. Attached pictures are parsed into Base64 streams and saved within the offline IndexedDB `db.thoughts` storage.
*   **Visual Thumbnails**: Previews appear as compact chips next to the input area before submission.
*   **Enlarge & View**: In the thought feed, attached pictures are rendered directly inside the cards. Clicking any preview thumbnail displays a full-screen, high-resolution overlay.

### The Tactical Interface (The Eye Widget)
In the bottom-right corner of the interface, you'll see a floating 👁️ Widget. Clicking this toggles your extended toolsuites, guaranteeing they are immediately handy regardless of which mode or menu you enter.

1. **🧠 Jarvis Connect:** A specialized interface interacting directly with the underlying AI configuration (Ollama).
2. **📅 Calendar Matrix:** Visual timelines of events mapping automatically. 
3. **👁️ OCR Vision Drop:** An optical drop-zone for ripping text out of raw images completely offline.

---

## ⚙️ Global Control & Personalization (`Ctrl + Shift + I`)

ThoughtHolder v6.0 introduces the **Global Settings Portal**, allowing you to tailor the OS to your specific operational needs.

### Operator Identity
The system now synchronizes your name across the Jarvis kernel and the UI. Updating your name in Settings immediately updates Jarvis's relational awareness of you.

### Custom Command Bindings
You can now redefine the primary hotkeys used to navigate the system:
- **System Settings**: Default `Ctrl + Shift + I`
- **Stealth Toggle**: Default `Ctrl + Shift + L` (Cloaks/Uncloaks hidden files)
- **Vault Entry**: Default `Ctrl + Shift + V` (Instant transition to Wine Cellar)

### Remote Jarvis IP (New in v6.0)
You can now connect the mobile application directly to a high-power PC running Ollama on the same local network. Enter your computer's local IP address under Settings -> Core, enabling deep remote inference from your handset.

### Security Management (Eradicate Locks)
If you lose access to a specific sub-layer or pattern, the **SECURITY MANAGEMENT** section allows you to selectively eradicate security locks (passwords/sequences). 
*Note: This removes the lock but preserves the data, allowing you to re-configure a new password.*

---

## 🦾 Engaging The Artificial Intelligence

ThoughtHolder possesses an autonomous AI system locally titled "Jarvis".

### The Interaction Leash
At the top level of the primary dashboard, you can click the small central pill indicating your "Leash" status:
- **Sleeping (Level 0):** Jarvis is disabled natively.
- **Reactive (Level 1):** Jarvis responds only when engaged.
- **Proactive Daemon (Level 2):** Jarvis activates an aggressive scanning parameter and will prompt you autonomously.

---

## 🛡️ Navigating Into Extreme Security

If you type `/vault` or use your custom hotkey, you enter **The Hydra Protocol**.

### Level 2: The Decoy "Wine Cellar"
Instead of a password prompt, the interface transforms into a passive, uninteresting "Personal Library." 

**How Do You Bypass the Illusion?**
- **Desktop:** Right-click the decoy media to open configuration; left-click consecutive times to unlock.
- **Mobile (New in v6.0):** Long-press the decoy media to configure setup target layers and click patterns; tap consecutive times to unlock.

### Level 4: The Arsenal
The Deep Arsenal is your encrypted workspace. It supports three types of authentication:
1. **Text Strings**: Standard secure passphrases.
2. **Numeric PINs**: Rapid 4-8 digit combinations.
3. **Picture Sequences**: Upload your own decoy images and select a hidden pattern to unlock.

---

## 🔄 Advanced Vault Orchestration (Transfer)

ThoughtHolder allows you to fluidly move intelligence between different levels of security using the **Relocation Engine**.

### Moving Intel to the Vault
- **Desktop:** Right-click any thought card on the main dashboard and select **"Encrypt & Move to Vault"**.
- **Mobile (New in new v6.0):** Long-press any thought card on the screen to trigger the **Stealth Action Sheet**, then select **"Encrypt & Vault"**.
A selection modal will appear:
- **Base Arsenal**: Moves data to the primary Level 4 layer.
- **Sub-Layers**: You can select existing sub-layers or create a new one (e.g., "Project-X") on the fly.

### Transferring Between Sub-Layers
Inside the Arsenal, each payload has a **"Transfer"** or relocation control. This allows you to instantly move data between different secure layers without returning to the Surface. On mobile, this is optimized into compact vertical action items.

---

## ⚡ Expert Hotkeys & Commands

| Command/Hotkey | Action |
|---|---|
| **`Ctrl + Shift + I`** | Open Global Settings / Personalization |
| **`Ctrl + Shift + L`** | Toggle Stealth Mode (Cloak/Uncloak hidden nodes) |
| **`Ctrl + Shift + V`** | Instant Transition to Wine Cellar |
| **`/setcode [word]`** | Establishes a SHA-256 recovery codeword |
| **`/recover [word]`** | Bypasses traditional auth using recovery codeword |
| **`/reassign`** | Activates the **Vault Recovery Protocol** for orphaned data |
| **`/reset_auth`** | Hard reset of the Vault security configuration |
| **`Shift + Enter`** | Auto-increment list numbering inside a `/todo` or task mode |
| **`🎤 (Mic Click)`** | Toggle Voice Input (Online streaming / Offline WASM Whisper fallback) |
| **`📎 (Paperclip)`** | Attach local images/files (stores as Base64 in offline database) |

---

## 📦 Import, Export, & Resilience

### Intelligent Merge
When importing a backup, the system performs an **Intelligent Merge**. It compares the timestamps of every node and ensures that your latest data is never overwritten by an older backup.

### Background Normalization (Self-Healing)
ThoughtHolder v6.0 includes a background **Normalization Engine**. It automatically scans your metadata for any type-corruption (e.g., data that was accidentally saved as a string instead of an array) and repairs it silently. 
*Note: This ensures that payloads never "disappear" from your sub-layers due to storage errors.*

---

## 🛠️ Troubleshooting & Support

If you experience "Invisible Pictures" or "One-Way Transfers," ensure you have the latest **System Logic v6.0** installed. 
- **Picture Reset**: If images don't show, use the "Eradicate Lock" feature in Settings and re-configure the picture sequence. This saves fresh binary assets to the DB.
- **Data Wipe**: For a complete nuclear reset of all local memory, use `/reset_db`. Use with extreme caution.
