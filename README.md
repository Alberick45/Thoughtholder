# Thoughtholder

> **Catch every idea before it disappears.**  
> A zero-friction, local-first thought capture system for **Android** and **Windows Desktop**.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows-blue)](https://github.com/Alberick45/Thoughtholder)
[![Architecture](https://img.shields.io/badge/Architecture-Local--First%20%7C%20SQLite-003B57?logo=sqlite)](https://sqlite.org)
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20Offline%20%26%20Private-success)](#-privacy--local-first)
[![License](https://img.shields.io/badge/Status-v1.0.0-gold)](#-downloads--installation)

---

## 💡 The Problem: Ideas Don’t Wait

Great ideas strike at the most inconvenient times: while walking, mid-lecture, during workouts, or right before falling asleep.

Traditional note-taking apps fail because they require too much friction:
- **Focus Disruption**: Unlocking the phone, navigating folder hierarchies, and picking tags forces your brain out of creative flow.
- **“I’ll remember it later” syndrome**: You won't. Crucial details vanish within minutes if not held immediately.
- **Scattered Chaos**: Notes end up fragmented across messaging apps, paper scraps, screenshots, and fleeting memories.
- **Cloud Lag**: Cloud-based apps spin or stutter when network connectivity is slow or unavailable.

**Thoughtholder eliminates this friction completely.** Capture now, organize when you're ready.

---

## ⚡ What Thoughtholder Does

Thoughtholder gives you an instant, always-ready capture pad across both your mobile device and your desktop workspace.

### 🎙️ 1-Tap Brain Dump (Voice & Text)
- **Zero-Wait Recording**: Open the app or tap the widget and speak immediately.
- **Screen-Off Background Recording**: Put your phone down and keep talking; recording continues uninterrupted even when the screen locks.
- **Quick Voice/Text Switch**: Instantly toggle between audio voice notes and fast typing.

### 🖥️ Desktop Command Center (Windows)
- **Global Summon Hotkey**: Press `Ctrl + Shift + B` from any application or game to summon the Brain Dump window immediately.
- **System Tray Background Daemon**: Runs quietly in the Windows notification tray without cluttering your taskbar.
- **Single-Instance Window Control**: Never opens accidental duplicate windows—re-launching focuses and restores the active window.

### 📥 Stream & Automatic Organization
- **Unsorted Inbox**: Raw thoughts land directly in a unified stream, completely free of forced upfront categorization.
- **Automatic Smart Titles**: Intelligent title generation creates clean, legible headers automatically so you never stare at blank notes.
- **Buckets**: Sort ideas into customized buckets (*School*, *Tasks*, *Projects*, etc.) when you have time to review.
- **Swipe Between Tabs**: Ergonomic, gesture-driven switching between Capture, Stream, and Buckets.
- **Keyboard-Safe Sheets**: Dynamic bottom sheets that automatically elevate above on-screen keyboards so action buttons and search bars are never hidden.

### 🔒 Privacy & Local-First Freedom
- **No Account Required**: No logins, no telemetry, no tracking, and no ads.
- **Offline SQLite Engine**: All ideas and buckets are stored locally on your device in standard SQLite.
- **Encrypted Bundles (`.thoughtbundle`)**: Export or import your entire notebook with authenticated **AES-256-GCM** encryption and **Argon2id** key derivation.
- **Local Pairing & Sync**: Direct device-to-device synchronization (BLE QuickLink & QR pairing) without passing through central cloud servers.

---

## 🏗️ Project Architecture & Structure

The repository is built as a unified cross-platform Flutter application backed by native platform runners for Windows and Android:

```text
thoughtholder/
├── thought_holder_flutter/          # Core Flutter application
│   ├── lib/
│   │   ├── main.dart                # App bootstrap & multi-platform initialization
│   │   ├── capture_screen.dart      # Voice/Text Brain Dump with screen-off audio capture
│   │   ├── stream_screen.dart       # Unified Stream (Unsorted & Sorted ideas, filter, search)
│   │   ├── idea_detail_screen.dart  # Idea viewer, editor, and bucket selector
│   │   ├── desktop_manager.dart     # Windows tray daemon, global hotkey (Ctrl+Shift+B), window manager
│   │   ├── database_helper.dart     # SQLite schema, migrations, and automatic undo snapshots
│   │   ├── thought_provider.dart    # Reactive state management and ranking engine
│   │   ├── services/
│   │   │   ├── thought_bundle_service.dart  # Encrypted .thoughtbundle export & safe import
│   │   │   ├── backup_service.dart          # Automatic pre-import database backups
│   │   │   ├── ble_sync_service.dart        # Peer-to-peer QuickLink BLE sync protocol
│   │   │   └── pairing_service.dart         # X25519 key exchange, SAS & QR pairing
│   │   ├── widgets/
│   │   │   ├── keyboard_safe_sheet.dart     # Keyboard-aware bottom sheets
│   │   │   └── swipe_tabs.dart              # Gesture-driven page switching
│   │   └── settings/                        # User preferences, theme, gestures, and audio settings
│   │
│   ├── windows/                     # Native Windows C++ Runner (Win32 window, tray, mutex, manifest)
│   ├── android/                     # Native Android runner (audio foreground service, permissions)
│   └── test/                        # Comprehensive unit and widget tests (126+ test suite)
│
└── website/                         # Web landing page and download showcase (index.html, assets)
```

---

## 📥 Downloads & Installation

Thoughtholder is available as an Android APK and a Windows native desktop application.

### 📱 Android Installation

1. **Download the APK**:
   - [Download `app-release.apk` (v1.0.0)](https://github.com/Alberick45/Thoughtholder/releases/download/v1.0.0/app-release.apk) *(~78 MB)*
2. **Install**:
   - Open the downloaded `.apk` file on your phone.
   - If Android prompts you, tap **Settings** and allow *Install unknown apps* for your browser or file manager.
   - If Google Play Protect shows a notice, tap **More details** → **Install anyway** *(standard for direct APK installs outside the Play Store)*.
3. **Permissions**:
   - Open Thoughtholder and grant **Microphone** permission when prompted for voice capture.

---

### 💻 Windows Desktop Installation

1. **Download the Windows Executable**:
   - [Download `thoughtholder-1.0.0-windows-x64.exe` (v1.0.0)](https://github.com/Alberick45/Thoughtholder/releases/download/v1.0.0/thoughtholder-1.0.0-windows-x64.exe)
2. **Launch & Shortcut Options**:
   - **Desktop Shortcut**: Launch via the **Thoughtholder** icon on your Desktop.
   - **Start Menu**: Search for `ThoughtHolder` in your Windows Start Menu.
   - **Run Dialog**: Press <kbd>Win</kbd> + <kbd>R</kbd>, type `ThoughtHolder`, and press <kbd>Enter</kbd>.
   - **Global Hotkey**: Press <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>B</kbd> from anywhere in Windows to trigger instant capture.

#### Local Installation Path
If already installed via the setup script, the program bundle lives at:
```text
C:\Users\<User>\AppData\Local\Programs\ThoughtHolder\thought_holder_flutter.exe
```

---

## 🛠️ Building from Source

To compile Thoughtholder yourself from source:

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (>= 3.11.0)
- **For Android**: Android Studio & Android SDK (API 34+)
- **For Windows**: Visual Studio 2022 with the *"Desktop development with C++"* workload

### Build Steps

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Alberick45/Thoughtholder.git
   cd Thoughtholder/thought_holder_flutter
   ```

2. **Install dependencies**:
   ```bash
   flutter pub get
   ```

3. **Run the test suite**:
   ```bash
   flutter test
   ```

4. **Build Android Release APK**:
   ```bash
   flutter build apk --release
   # Output: build/app/outputs/flutter-apk/app-release.apk
   ```

5. **Build Windows Desktop Executable**:
   ```bash
   flutter build windows --release
   # Output: build/windows/x64/runner/Release/thought_holder_flutter.exe
   ```

---

## 🛡️ Security & Integrity

- **VirusTotal Scan**: You can upload any build or APK directly to [VirusTotal](https://www.virustotal.com) for independent third-party multi-engine verification.
- **SHA-256 Fingerprint**: Verified against release bundles to prevent tampering or corruption during transit.

---

## 📄 License & Attribution

Built with passion by **A3PK Labs** · *Build. Break. Learn. Repeat.*
