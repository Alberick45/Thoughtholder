# How ThoughtHolder Works

A plain-language guide to how ThoughtHolder organizes your ideas, where your information lives, and what happens step by step when you use the app.

---

## 1. Map of the App

ThoughtHolder has three main tabs along the bottom, plus dedicated focus views:

```
[ Capture Tab ]         [ Stream Tab ]             [ Settings Menu ]
  - Type text             - Sorted View              - Look & Feel (Theme)
  - Record voice          - Unsorted Queue           - Ideas & Buckets
                          - Bucket Focus Page        - Voice & Whisper AI
                          - History (Done Ideas)     - Sound Effects
                          - 3D Trash Can             - Notifications
                                                     - Devices & Sync
                                                     - Computer (Tray/Hotkey)
```

- **Stream Screen (`lib/stream_screen.dart`)**: Your daily workspace. 
  - **Sorted**: Shows the single highest-priority idea ("Start here" card) and the "View buckets" button to browse your folders.
  - **Unsorted**: Shows your fresh inbox, one thought at a time, so you can quickly decide where it belongs without feeling overwhelmed.
- **Bucket Focus Page (`lib/stream_screen.dart`)**: Opens when you tap a bucket. It hides the bottom navigation bar and trash can so you can focus entirely on that topic, filter ideas by date, or search within that bucket.
- **Capture Screen (`lib/capture_screen.dart`)**: Quick entry. Has a large Record button to dictate a thought and a text box to type one.
- **History Screen (`lib/history_screen.dart`)**: Where finished ideas go. You can review them, search them, or put them back into action anytime.
- **Trash Screen (`lib/stream_screen.dart`)**: Accessed by tapping the floating trash button. Holds discarded thoughts so you can restore them or permanently empty them.
- **Duplicate Finder (`lib/duplicate_finder_screen.dart`)**: Scans your ideas for duplicates with matching text and lets you combine or clean them up.
- **Settings Screen (`lib/settings_modal.dart` & `lib/settings/`)**: Organizes preferences into seven clear groups.

---

## 2. Where Your Data Lives

ThoughtHolder keeps your data locally on your computer or phone so it works completely offline:

| Kind of Data | Where It Is Stored | Exact File Path |
| :--- | :--- | :--- |
| **Ideas & Buckets** | Local SQLite Database | `AppData\Roaming\com.example\ThoughtHolder\databases\thoughts.db` (Windows)<br>`databases/thoughts.db` (Android) |
| **Preferences & Settings** | Hive Key-Value Box | `AppData\Roaming\com.example\ThoughtHolder\thought_holder_settings.hive` |
| **Secret Pairing Keys** | OS Secure Storage (Credential Vault) | Windows Credential Manager / Android KeyStore |
| **Voice Recordings** | Temporary Audio Files | Temporary cache directory (e.g. `recording_temp.wav`), deleted once transcribed |
| **Cloud Backups (Optional)** | Google Drive App Data | Hidden private folder on Google Drive (`thought_holder_backup.json`) |

---

## 3. What Happens Step-by-Step

### (a) When You Type an Idea
1. You type your thought into the text box on the Capture screen and tap Save.
2. The app assigns the idea a globally unique identifier (UUID v4) and auto-generates a clean title.
3. The idea is saved to the SQLite database with `status = 'active'`, `done = 0`, and `bucket = null`.
4. A pleasant save sound plays, and your new thought lands at the top of your **Unsorted** queue.

### (b) When You Record a Voice Idea
1. You tap the Record button. The microphone starts listening, and the app mutes interface sounds so they don't get recorded.
2. While you speak, audio is written to a temporary WAV file on your device.
3. When you tap Stop, the app sends the audio to the Groq Whisper AI service (if configured) or your device's built-in speech recognition to turn voice into written text.
4. If transcription succeeds, the audio is converted to a text idea and saved to **Unsorted**. The temporary sound file is deleted.
5. If you have no internet or Groq is unreachable, the audio file is preserved safely so it can be transcribed later without losing what you said.

### (c) When You Sort an Idea
1. On the Unsorted screen, you tap one of your buckets (or tap "Choose a bucket").
2. The app updates the idea's `bucket` column in the database and records the time of the change.
3. The idea immediately leaves Unsorted and moves into its new bucket.
4. A confirmation bar appears with an **Undo** button in case you tapped the wrong bucket by accident.

### (d) When You Mark an Idea Done
1. You tap "Mark done" on an idea card.
2. The app updates `done = 1`, `status = 'completed'`, and records `done_at` with the current time.
3. The idea leaves your active queue and moves to **History**.
4. A completion tone plays, and an Undo notification gives you 5 seconds to put it back immediately.

### (e) When You Trash and Restore an Idea
1. You open the `⋯` menu on an idea card and tap "Move to Trash".
2. The app sets `trashed = 1` and `status = 'vaulted_trash'`. It disappears from your active lists.
3. To restore it, tap the 3D trash button in the bottom right corner, find the thought, and tap "Restore". It returns exactly where it was before.
4. If you tap "Delete forever", the thought is permanently removed, and a tombstone (a record that it was deleted) is saved so other devices don't accidentally bring it back during sync.

### (f) When You Back Up and Restore
1. **Backup**: SQLite's `VACUUM INTO` creates an exact, frozen copy of `thoughts.db` even while the app is running.
2. **Restore**: Replacing the live database file with a verified backup restores all thoughts, buckets, and history exactly as they were at that snapshot.

### (g) When You Sync Between Two Devices
1. Two nearby devices connect directly over Bluetooth Low Energy (BLE) without needing the internet.
2. They compare timestamps (Hybrid Logical Clocks) to see what changed on each side since the last sync.
3. Newer edits win automatically. If an idea was edited on both devices while disconnected, a conflict copy is preserved in Unsorted so you never lose either version.
