# ThoughtHolder Data Map

This document describes every table, column, and setting used in ThoughtHolder, explains what each field is for in plain language, highlights which items contain private personal information, and lists the exact files that read and write them.

---

## 1. Database Table: `thoughts`
The primary table holding all your active, finished, and trashed ideas.

| Column | Type | Privacy Status | Plain-Language Description | Code That Reads/Writes |
| :--- | :--- | :--- | :--- | :--- |
| `id` | TEXT PRIMARY KEY | Metadata | Globally unique identifier (UUID v4 or legacy hash). | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart), [thought_provider.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/thought_provider.dart) |
| `thought_id` | TEXT | Metadata | Legacy display code (e.g., `LOG-1234`). | [thought_provider.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/thought_provider.dart) |
| `content` | TEXT | **PRIVATE** | The actual text of your idea or transcript. | [capture_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/capture_screen.dart), [stream_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/stream_screen.dart) |
| `title` | TEXT | **PRIVATE** | Short headline or auto-generated summary title. | [title_generator.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/utils/title_generator.dart), [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `title_source` | TEXT | Metadata | `'auto'` if computer generated, `'user'` if you edited it. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `type` | TEXT | Metadata | Input method: `'text'` or `'voice'`. | [capture_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/capture_screen.dart) |
| `status` | TEXT | Metadata | Lifecycle state: `'active'`, `'completed'`, or `'vaulted_trash'`. | [thought_provider.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/thought_provider.dart) |
| `tags` | TEXT | **PRIVATE** | Comma-separated category tags. | [thought_provider.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/thought_provider.dart) |
| `summary` | TEXT | **PRIVATE** | Optional short summary note. | [thought_provider.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/thought_provider.dart) |
| `created_at` | INTEGER | Metadata | Exact millisecond timestamp when the idea was created. | [thought_provider.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/thought_provider.dart) |
| `last_viewed_at`| INTEGER | Metadata | Timestamp when the idea was last opened or inspected. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `stale_score` | INTEGER | Metadata | Priority factor measuring how long an idea has sat idle. | [thought_provider.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/thought_provider.dart) |
| `linked_thoughts`| TEXT | Metadata | JSON list of other thought IDs connected to this one. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `bucket` | TEXT | Metadata | Name of the bucket this idea is filed into (null if Unsorted). | [stream_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/stream_screen.dart) |
| `bucket_id` | TEXT | Metadata | Unique ID of the bucket (prevents broken links on rename). | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `when_val` | TEXT | Metadata | Urgency ranking choice: `'Today'`, `'Soon'`, or `'Later'`. | [stream_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/stream_screen.dart) |
| `time_val` | TEXT | Metadata | Effort ranking choice: `'Quick'`, `'Medium'`, or `'Long'`. | [stream_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/stream_screen.dart) |
| `done` | INTEGER | Metadata | `1` if marked done/finished, `0` if active. | [history_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/history_screen.dart), [stream_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/stream_screen.dart) |
| `trashed` | INTEGER | Metadata | `1` if moved to trash, `0` if active. | [stream_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/stream_screen.dart) |
| `done_at` | INTEGER | Metadata | Timestamp when marked done (null if still active). | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `trashed_at` | INTEGER | Metadata | Timestamp when moved to trash (null if not in trash). | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `edited_at` | INTEGER | Metadata | Timestamp of last manual edit to title or content. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `updated_at` | TEXT | Metadata | Hybrid Logical Clock (HLC) string used for sync conflict resolution. | [sync_identity.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/sync_identity.dart) |
| `updated_by` | TEXT | Metadata | Device ID that performed the most recent update. | [sync_identity.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/sync_identity.dart) |
| `revision` | INTEGER | Metadata | Incremental counter bumped on every modification. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |

---

## 2. Database Table: `buckets`
Defines folders where ideas are categorized.

| Column | Type | Privacy Status | Plain-Language Description | Code That Reads/Writes |
| :--- | :--- | :--- | :--- | :--- |
| `name` | TEXT PRIMARY KEY | Metadata | Bucket title (e.g., "Tasks", "Projects"). | [thought_provider.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/thought_provider.dart), [stream_screen.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/stream_screen.dart) |
| `id` | TEXT | Metadata | Unique bucket identifier (UUID v4). | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `icon` | TEXT | Metadata | Key for the icon shown on the bucket (e.g., `'briefcase'`). | [app_theme.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/app_theme.dart), [create_bucket_sheet.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/settings/create_bucket_sheet.dart) |
| `created_at` | INTEGER | Metadata | Timestamp when this bucket was created. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `updated_at` | TEXT | Metadata | HLC timestamp used for sync. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `updated_by` | TEXT | Metadata | Device ID that modified the bucket. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `revision` | INTEGER | Metadata | Revision counter bumped on update. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |

---

## 3. Database Table: `deleted_records` (Tombstones)
Remembers which thoughts and buckets have been deleted permanently, so synchronization doesn't accidentally recreate them from another device.

| Column | Type | Privacy Status | Plain-Language Description | Code That Reads/Writes |
| :--- | :--- | :--- | :--- | :--- |
| `id` | TEXT PRIMARY KEY | Metadata | Unique ID of the deleted thought or bucket. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `type` | TEXT | Metadata | Object type: `'thought'` or `'bucket'`. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `deleted_at` | INTEGER | Metadata | Timestamp when permanently deleted. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `updated_at` | TEXT | Metadata | HLC timestamp of deletion. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `updated_by` | TEXT | Metadata | Device ID that deleted the item. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |

---

## 4. Database Table: `bucket_aliases`
Tracks merged buckets when the same bucket was created independently on two devices.

| Column | Type | Privacy Status | Plain-Language Description | Code That Reads/Writes |
| :--- | :--- | :--- | :--- | :--- |
| `alias_id` | TEXT PRIMARY KEY | Metadata | Former bucket ID that was merged away. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `canonical_id` | TEXT | Metadata | The surviving master bucket ID. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |
| `created_at` | INTEGER | Metadata | Timestamp of the merge operation. | [database_helper.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/database_helper.dart) |

---

## 5. Settings Storage (Hive Box: `thought_holder_settings.hive`)
Stores user preferences on disk.

| Setting Key | Type | Privacy Status | Plain-Language Description | Code That Reads/Writes |
| :--- | :--- | :--- | :--- | :--- |
| `theme_mode` | String | Preference | Active theme: `'dark'`, `'light'`, or `'calm'`. | [settings_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/settings_service.dart) |
| `groq_api_key` | String | **PRIVATE / SECRET** | Secret API key used for Groq Whisper transcription. *(Currently stored in plain Hive settings instead of OS Secure Storage).* | [settings_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/settings_service.dart), [voice_transcription_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/voice_transcription_service.dart) |
| `sounds_enabled` | bool | Preference | Master on/off switch for application audio cues. | [settings_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/settings_service.dart) |
| `sound_volume` | double | Preference | Volume level from 0.0 to 0.8 (capped at 80%). | [settings_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/settings_service.dart) |
| `unsorted_order` | String | Preference | `'newest'` (default) or `'oldest'` first. | [settings_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/settings_service.dart) |
| `bucket_order` | String | Preference | `'ideas'` (most ideas first) or `'creation'` order. | [settings_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/settings_service.dart) |
| `device_id` | String | Metadata | Unique UUID identifying this specific computer or phone. | [sync_identity.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/sync_identity.dart) |
| `device_name` | String | Metadata | Human-readable name (e.g., "Albert's Laptop"). | [settings_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/settings_service.dart) |
| `paired_devices` | Map | Metadata | Known Bluetooth paired devices and their last sync dates. | [settings_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/settings_service.dart) |

---

## 6. Secure Storage (Operating System Credential Vault)
Stores cryptographic secrets that must never be written into normal application files.

| Secret Key | Privacy Status | Plain-Language Description | Code That Reads/Writes |
| :--- | :--- | :--- | :--- |
| `ps_key_<peerDeviceId>` | **SECRET** | 256-bit AES shared encryption key generated during Bluetooth pairing to encrypt all sync data in transit. | [secure_storage_service.dart](file:///c:/Users/PAAPA/Desktop/testwritingapp/thought_holder_flutter/lib/secure_storage_service.dart) |
