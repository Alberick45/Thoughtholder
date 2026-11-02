# ThoughtHolder Glossary

Every technical term used in this project, explained in one plain sentence.

---

### Data & Storage
- **SQLite**: A lightweight, standalone database engine that stores all your ideas and buckets directly in a single file on your device without needing a server.
- **VACUUM INTO**: An SQLite command that creates an exact, frozen backup copy of an open database without interrupting or corrupting live operations.
- **PRAGMA integrity_check**: An internal database diagnostic command that verifies every page, index, and table is healthy and uncorrupted.
- **UUID (Universally Unique Identifier)**: A 36-character randomly generated string that guarantees an idea or bucket has an ID unique across all devices in the world.
- **Hive**: A fast, lightweight local storage system used in Flutter to save your settings and preferences on disk.
- **Secure Storage**: A protected storage area provided by your computer or phone's operating system (like Windows Credential Manager or Android KeyStore) where passwords and encryption keys are kept encrypted.
- **Tombstone**: A small marker record left behind when you delete an idea forever so that other devices know not to bring it back during synchronization.
- **Upsert**: A safe database operation that inserts a new item if it does not exist, or updates only the newer fields if it already exists.
- **Monotonic Revision**: A counter number that only ever increases with each edit, ensuring your app can always distinguish older versions from newer ones.

---

### Synchronization & Networking
- **HLC (Hybrid Logical Clock)**: A timestamp format that combines the real clock time with a counter number to reliably determine which device made a change first, even if one device's clock is slightly off.
- **CRDT (Conflict-free Replicated Data Type)**: A mathematical approach to structuring data so two independent devices can merge their changes seamlessly without losing work.
- **BLE (Bluetooth Low Energy)**: A low-power wireless standard that allows your phone and computer to talk directly to each other without using your Wi-Fi network or cellular data.
- **GATT (Generic Attribute Profile)**: The structured rulebook Bluetooth devices use to organize and send chunks of data back and forth.
- **Peripheral Mode**: A Bluetooth state where your device acts as a receiver, advertising a signal so nearby devices can discover and connect to it.
- **Characteristic**: A specific data channel or mailbox within a Bluetooth connection used to read, write, or stream bytes.
- **X25519 Key Exchange**: A secure mathematical handshake where two devices exchange public codes to compute an identical secret encryption key without eavesdroppers being able to figure it out.
- **SAS (Short Authentication String)**: A 6-digit number derived from an encryption key that you compare on both screens to visually confirm that no imposter intercepted the connection.
- **HMAC-SHA256**: A cryptographic fingerprint algorithm that verifies a message came from a known paired device and was not altered in transit.
- **Google Drive AppData**: A hidden private folder in your Google Drive account accessible only by ThoughtHolder to store encrypted backup snapshots.

---

### Voice & Intelligence
- **Whisper AI**: An artificial intelligence speech-recognition model created by OpenAI that turns recorded spoken audio into accurate written text.
- **Groq API**: A high-speed cloud service that runs the Whisper AI model in under two seconds to transcribe your voice notes.
- **STT (Speech-to-Text)**: The built-in software on your device that converts spoken speech into written words without using an external internet service.

---

### User Interface & System
- **Debounce**: A programming technique that waits a fraction of a second after you finish typing before running a search, keeping the app smooth and responsive.
- **System Tray**: The small notification area on your computer taskbar where ThoughtHolder can stay running quietly in the background when minimized.
- **Global Hotkey**: A keyboard shortcut (like Ctrl+Shift+B) that opens ThoughtHolder and starts recording from anywhere on your computer, even when other apps are open.
- **Touch Target**: The clickable or tappable rectangular area of a button, designed to be at least 48 pixels wide and tall so your finger never misses it.
- **Contrast Ratio**: A measurement of the visual brightness difference between text and its background to ensure reading is comfortable and accessible.
- **BuildContext**: An internal Flutter reference that keeps track of where a visual button or card sits in the screen layout tree.
- **dispose()**: A cleanup function that releases memory, stops timers, and closes audio players when a screen or pop-up is closed.
- **MethodChannel**: A bridge that lets Flutter code trigger native operating system features, like Windows window management or Android background audio.
