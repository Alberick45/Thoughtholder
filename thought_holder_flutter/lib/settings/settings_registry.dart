import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../thought_provider.dart';
import '../sound_service.dart';
import '../desktop_manager.dart';
import '../voice_transcription_service.dart';
import '../google_drive_service.dart';
import '../ble_sync_screen.dart';
import '../paired_devices_screen.dart';
import '../history_screen.dart';
import '../duplicate_finder_screen.dart';
import '../notifications_settings_screen.dart';
import '../connect_groq_modal.dart';
import '../starter_buckets_screen.dart';
import 'settings_widgets.dart';

/// Single item representing a configurable setting.
class SettingEntry {
  final String id;
  final String title;
  final String description;
  final String group;
  final bool isAdvanced;
  final bool isDesktopOnly;
  final List<String> keywords;
  final Widget Function(BuildContext context, SettingsService settings, AppColors colors) builder;

  const SettingEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.group,
    this.isAdvanced = false,
    this.isDesktopOnly = false,
    this.keywords = const [],
    required this.builder,
  });

  /// Case-insensitive match across title, description, group name, and keywords.
  bool matches(String query) {
    if (query.trim().isEmpty) return false;
    final lower = query.trim().toLowerCase();
    final words = lower.split(RegExp(r'\s+'));
    final haystack = '$title $description $group ${keywords.join(' ')}'.toLowerCase();
    return words.any((w) => haystack.contains(w));
  }
}

/// Central registry of all settings entries.
class SettingsRegistry {
  static List<SettingEntry> getEntries() {
    return [
      // ==========================================
      // GROUP 1: Look and feel
      // ==========================================
      SettingEntry(
        id: 'theme_mode',
        title: 'Theme',
        description: 'Choose Dark, Soft light, or Calm theme',
        group: 'Look and feel',
        keywords: ['dark', 'light', 'calm', 'theme', 'color', 'mode', 'appearance', 'look', 'feel'],
        builder: (context, settings, colors) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Theme',
                style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose the interface appearance for ThoughtHolder.',
                style: appFont(color: colors.mute, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildThemeOption('Dark', 'dark', Icons.dark_mode_outlined, settings, colors),
                  const SizedBox(width: 8),
                  _buildThemeOption('Soft light', 'light', Icons.light_mode_outlined, settings, colors),
                  const SizedBox(width: 8),
                  _buildThemeOption('Calm', 'calm', Icons.nightlight_outlined, settings, colors),
                ],
              ),
            ],
          );
        },
      ),

      // ==========================================
      // GROUP 2: Ideas and buckets
      // ==========================================
      SettingEntry(
        id: 'unsorted_order',
        title: 'Unsorted order',
        description: 'Choose whether newest or oldest ideas appear first in Unsorted',
        group: 'Ideas and buckets',
        keywords: ['unsorted', 'order', 'newest', 'oldest', 'queue', 'ideas'],
        builder: (context, settings, colors) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unsorted order',
                style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose whether newest or oldest ideas appear first in Unsorted.',
                style: appFont(color: colors.mute, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildSegmentedOption(
                    label: 'Newest first (default)',
                    isSelected: settings.unsortedOrder == 'newest',
                    onTap: () => settings.setUnsortedOrder('newest'),
                    colors: colors,
                  ),
                  const SizedBox(width: 8),
                  _buildSegmentedOption(
                    label: 'Oldest first',
                    isSelected: settings.unsortedOrder == 'oldest',
                    onTap: () => settings.setUnsortedOrder('oldest'),
                    colors: colors,
                  ),
                ],
              ),
            ],
          );
        },
      ),
      SettingEntry(
        id: 'bucket_order',
        title: 'Sorted bucket order',
        description: 'Order buckets by most ideas first or creation sequence',
        group: 'Ideas and buckets',
        keywords: ['sorted', 'bucket', 'order', 'ideas', 'creation', 'sequence'],
        builder: (context, settings, colors) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sorted bucket order',
                style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                'Order buckets by number of ideas or creation sequence.',
                style: appFont(color: colors.mute, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildSegmentedOption(
                    label: 'Most ideas first',
                    isSelected: settings.bucketOrder == 'ideas',
                    onTap: () => settings.setBucketOrder('ideas'),
                    colors: colors,
                  ),
                  const SizedBox(width: 8),
                  _buildSegmentedOption(
                    label: 'Creation order',
                    isSelected: settings.bucketOrder == 'creation',
                    onTap: () => settings.setBucketOrder('creation'),
                    colors: colors,
                  ),
                ],
              ),
            ],
          );
        },
      ),
      SettingEntry(
        id: 'history_screen',
        title: 'History',
        description: 'Review and restore finished ideas',
        group: 'Ideas and buckets',
        keywords: ['history', 'finished', 'completed', 'done', 'put back', 'ideas'],
        builder: (context, settings, colors) {
          final thoughtProvider = context.watch<ThoughtProvider>();
          final finishedCount = thoughtProvider.doneCount;
          final finishedText = '$finishedCount finished idea${finishedCount == 1 ? '' : 's'}';

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.history, color: colors.gold, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'History',
                          style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          finishedText,
                          style: appFont(color: colors.mute, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.mute, size: 20),
                ],
              ),
            ),
          );
        },
      ),
      SettingEntry(
        id: 'find_duplicates',
        title: 'Find duplicates',
        description: 'Review and merge ideas with identical text',
        group: 'Ideas and buckets',
        keywords: ['duplicates', 'duplicate', 'merge', 'identical', 'find', 'ideas'],
        builder: (context, settings, colors) {
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DuplicateFinderScreen()),
              );
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.copy_all_outlined, color: colors.gold, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Find duplicates',
                          style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Review and merge ideas with identical text',
                          style: appFont(color: colors.mute, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.mute, size: 20),
                ],
              ),
            ),
          );
        },
      ),
      SettingEntry(
        id: 'starter_buckets',
        title: 'Starter buckets',
        description: 'Add standard starter buckets anytime',
        group: 'Ideas and buckets',
        isAdvanced: true,
        keywords: ['starter', 'buckets', 'to do', 'deep ideas', 'reference', 'inbox later', 'life', 'health'],
        builder: (context, settings, colors) {
          final thoughtProvider = context.watch<ThoughtProvider>();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Starter buckets',
                style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Add any of the standard starter buckets anytime.',
                style: appFont(color: colors.mute, fontSize: 12),
              ),
              const SizedBox(height: 10),
              ...kStarterBuckets.map((starter) {
                final name = starter.name;
                final iconKey = starter.iconKey;
                final desc = starter.description;
                final iconData = kBucketIcons[iconKey] ?? Icons.folder_outlined;
                final bool isExisting = thoughtProvider.buckets.any((b) =>
                    (b['name'] as String).trim().toLowerCase() ==
                    name.trim().toLowerCase());

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5.0),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colors.bg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.line),
                        ),
                        child: Icon(iconData, color: colors.gold, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              desc,
                              style: appFont(color: colors.mute, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isExisting)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: colors.bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.line),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 14, color: colors.done),
                              const SizedBox(width: 4),
                              Text('Added', style: appFont(color: colors.mute, fontSize: 12)),
                            ],
                          ),
                        )
                      else
                        SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: () => thoughtProvider.addBucket(name, icon: iconKey),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ],
          );
        },
      ),

      // ==========================================
      // GROUP 3: Voice and AI
      // ==========================================
      SettingEntry(
        id: 'groq_wizard',
        title: 'Set up Groq (4 steps)',
        description: 'Connect and configure free Groq Whisper AI transcription',
        group: 'Voice and AI',
        keywords: ['groq', 'wizard', 'setup', 'key', 'whisper', 'ai', 'voice', 'mic', 'microphone'],
        builder: (context, settings, colors) {
          return SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const ConnectGroqModal(),
                );
              },
              icon: const Icon(Icons.key, size: 18),
              label: const Text('Set up Groq (4 steps)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                foregroundColor: Colors.black,
                textStyle: appFont(fontWeight: FontWeight.bold, fontSize: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          );
        },
      ),
      SettingEntry(
        id: 'use_whisper_first',
        title: 'Use Whisper AI first',
        description: 'Uses Groq Whisper Large V3 Turbo when online, with offline fallback',
        group: 'Voice and AI',
        keywords: ['whisper', 'groq', 'ai', 'voice', 'primary', 'mic', 'microphone', 'transcription'],
        builder: (context, settings, colors) {
          return SettingsSwitchRow(
            title: 'Use Whisper AI first',
            subtitle: 'Uses Groq Whisper Large V3 Turbo when online, with automatic offline fallback to device',
            value: settings.useWhisperAsPrimary,
            onChanged: (val) => settings.setUseWhisperAsPrimary(val),
            colors: colors,
          );
        },
      ),
      SettingEntry(
        id: 'groq_api_key',
        title: 'Groq API key',
        description: 'Manage your private Groq API key (masked)',
        group: 'Voice and AI',
        keywords: ['groq', 'api', 'key', 'gsk', 'token', 'secret', 'mic', 'whisper'],
        builder: (context, settings, colors) {
          return _GroqKeyInlineControl(settings: settings, colors: colors);
        },
      ),
      SettingEntry(
        id: 'test_connection',
        title: 'Test connection',
        description: 'Audition and test live reachability to Groq Whisper AI',
        group: 'Voice and AI',
        keywords: ['test', 'connection', 'groq', 'reachability', 'check', 'whisper', 'mic'],
        builder: (context, settings, colors) {
          return _TestConnectionInlineControl(settings: settings, colors: colors);
        },
      ),
      SettingEntry(
        id: 'names_and_terms',
        title: 'Names and terms',
        description: 'Prompt priming for names, local towns, and technical jargon',
        group: 'Voice and AI',
        isAdvanced: true,
        keywords: ['prompt', 'priming', 'names', 'terms', 'vocabulary', 'dictionary', 'jargon', 'spelling', 'mic', 'whisper'],
        builder: (context, settings, colors) {
          return _PromptPrimingInlineControl(settings: settings, colors: colors);
        },
      ),

      // ==========================================
      // GROUP 4: Sounds
      // ==========================================
      SettingEntry(
        id: 'sounds_master',
        title: 'Sounds',
        description: 'Master switch for short, soft feedback sounds',
        group: 'Sounds',
        keywords: ['sound', 'audio', 'feedback', 'master', 'mute', 'tones', 'speaker'],
        builder: (context, settings, colors) {
          return SettingsSwitchRow(
            title: 'Sounds',
            subtitle: 'Play soft feedback sounds for buttons and actions',
            value: settings.soundsEnabled,
            onChanged: (val) async {
              await settings.setSoundsEnabled(val);
              await settings.setSoundPromptAnswered(true);
              if (val) {
                SoundService.instance.play(SoundEvent.switchOn, settings: settings, preview: true);
              }
            },
            colors: colors,
          );
        },
      ),
      SettingEntry(
        id: 'sound_volume',
        title: 'Volume',
        description: 'Master sound volume slider capped at 80%',
        group: 'Sounds',
        keywords: ['volume', 'level', 'sound', 'slider', 'loudness', 'soft', 'audio'],
        builder: (context, settings, colors) {
          final vol = settings.soundVolume;
          final volPct = (vol * 100).round();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Volume', style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14)),
                  Text('$volPct%', style: appFont(color: colors.gold, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 6),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: colors.gold,
                  inactiveTrackColor: colors.bg,
                  thumbColor: colors.gold,
                ),
                child: Slider(
                  value: vol,
                  min: 0.0,
                  max: 0.80,
                  divisions: 16,
                  onChanged: (val) => settings.setSoundVolume(val),
                  onChangeEnd: (val) {
                    SoundService.instance.play(SoundEvent.save, settings: settings, preview: true);
                  },
                ),
              ),
            ],
          );
        },
      ),
      SettingEntry(
        id: 'sound_style',
        title: 'Sound style',
        description: 'Choose Soft (organic felt/wood) or Crisp (glass/bell)',
        group: 'Sounds',
        keywords: ['style', 'soft', 'crisp', 'sound', 'timbre', 'bell', 'tone'],
        builder: (context, settings, colors) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sound style', style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () async {
                          await settings.setSoundStyle('soft');
                          SoundService.instance.play(SoundEvent.save, settings: settings, preview: true);
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: settings.soundStyle == 'soft' ? colors.goldBg : colors.bg,
                          side: BorderSide(
                            color: settings.soundStyle == 'soft' ? colors.gold : colors.line,
                            width: settings.soundStyle == 'soft' ? 1.8 : 1.0,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'Soft (default)',
                          style: appFont(
                            color: settings.soundStyle == 'soft' ? colors.gold : colors.mute,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () async {
                          await settings.setSoundStyle('crisp');
                          SoundService.instance.play(SoundEvent.save, settings: settings, preview: true);
                        },
                        style: OutlinedButton.styleFrom(
                          backgroundColor: settings.soundStyle == 'crisp' ? colors.goldBg : colors.bg,
                          side: BorderSide(
                            color: settings.soundStyle == 'crisp' ? colors.gold : colors.line,
                            width: settings.soundStyle == 'crisp' ? 1.8 : 1.0,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          'Crisp',
                          style: appFont(
                            color: settings.soundStyle == 'crisp' ? colors.gold : colors.mute,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      SettingEntry(
        id: 'sound_group_taps',
        title: 'Taps and buttons',
        description: 'Button presses, tab switches, and popups',
        group: 'Sounds',
        isAdvanced: true,
        keywords: ['tap', 'click', 'button', 'popup', 'switch', 'sound'],
        builder: (context, settings, colors) {
          return _buildSoundGroupRow(
            title: 'Taps and buttons',
            subtitle: 'Button presses, tab switches, and popups',
            value: settings.soundGroupTaps,
            onChanged: (v) => settings.setSoundGroupTaps(v),
            onTest: () => SoundService.instance.play(SoundEvent.tap, settings: settings, preview: true),
            colors: colors,
          );
        },
      ),
      SettingEntry(
        id: 'sound_group_swipes',
        title: 'Swipes and slides',
        description: 'Tab swiping, bucket slider, and card swipe',
        group: 'Sounds',
        isAdvanced: true,
        keywords: ['swipe', 'slide', 'carousel', 'movement', 'sound'],
        builder: (context, settings, colors) {
          return _buildSoundGroupRow(
            title: 'Swipes and slides',
            subtitle: 'Tab swiping, bucket slider, and card swipe',
            value: settings.soundGroupSwipes,
            onChanged: (v) => settings.setSoundGroupSwipes(v),
            onTest: () => SoundService.instance.play(SoundEvent.swipe, settings: settings, preview: true),
            colors: colors,
          );
        },
      ),
      SettingEntry(
        id: 'sound_group_saving',
        title: 'Saving and finishing',
        description: 'Saving thoughts, filing into buckets, and marking done',
        group: 'Sounds',
        isAdvanced: true,
        keywords: ['save', 'drop', 'done', 'finish', 'sound', 'chime'],
        builder: (context, settings, colors) {
          return _buildSoundGroupRow(
            title: 'Saving and finishing',
            subtitle: 'Saving thoughts, filing into buckets, and marking done',
            value: settings.soundGroupSaving,
            onChanged: (v) => settings.setSoundGroupSaving(v),
            onTest: () => SoundService.instance.play(SoundEvent.done, settings: settings, preview: true),
            colors: colors,
          );
        },
      ),
      SettingEntry(
        id: 'sound_group_deleting',
        title: 'Deleting and warnings',
        description: 'Move to trash, delete forever, undo, and error alerts',
        group: 'Sounds',
        isAdvanced: true,
        keywords: ['delete', 'trash', 'warning', 'undo', 'error', 'sound'],
        builder: (context, settings, colors) {
          return _buildSoundGroupRow(
            title: 'Deleting and warnings',
            subtitle: 'Move to trash, delete forever, undo, and error alerts',
            value: settings.soundGroupDeleting,
            onChanged: (v) => settings.setSoundGroupDeleting(v),
            onTest: () => SoundService.instance.play(SoundEvent.trash, settings: settings, preview: true),
            colors: colors,
          );
        },
      ),
      SettingEntry(
        id: 'sound_group_typing',
        title: 'Typing key clicks',
        description: 'Plays a very soft sound for each key press',
        group: 'Sounds',
        isAdvanced: true,
        keywords: ['typing', 'key', 'click', 'keyboard', 'keystroke', 'sound'],
        builder: (context, settings, colors) {
          return _buildSoundGroupRow(
            title: 'Typing',
            subtitle: 'Plays a very soft sound for each key. Some people find this distracting.',
            value: settings.soundGroupTyping,
            onChanged: (v) => settings.setSoundGroupTyping(v),
            onTest: () => SoundService.instance.play(SoundEvent.key, settings: settings, preview: true),
            colors: colors,
          );
        },
      ),

      // ==========================================
      // GROUP 5: Notifications
      // ==========================================
      SettingEntry(
        id: 'notifications_row',
        title: 'Notifications and reminders',
        description: 'Start here nudges, gentle capture reminders, and quiet hours',
        group: 'Notifications',
        keywords: ['notifications', 'nudges', 'reminders', 'quiet hours', 'alerts', 'schedule'],
        builder: (context, settings, colors) {
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsSettingsScreen()),
              );
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_active_outlined, color: colors.gold, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications and reminders',
                          style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Start here nudges, capture reminders & quiet hours',
                          style: appFont(color: colors.mute, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.mute, size: 20),
                ],
              ),
            ),
          );
        },
      ),

      // ==========================================
      // GROUP 6: Devices and backup
      // ==========================================
      SettingEntry(
        id: 'ble_sync_row',
        title: 'Sync with nearby device',
        description: 'Merge ideas and buckets offline over Bluetooth',
        group: 'Devices and backup',
        keywords: ['sync', 'bluetooth', 'ble', 'offline', 'nearby', 'merge', 'device'],
        builder: (context, settings, colors) {
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BleSyncScreen()),
              );
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.bluetooth_connected, color: colors.gold, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sync with nearby device',
                          style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Merge ideas and buckets offline over Bluetooth',
                          style: appFont(color: colors.mute, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.mute, size: 20),
                ],
              ),
            ),
          );
        },
      ),
      SettingEntry(
        id: 'paired_devices_row',
        title: 'Paired devices',
        description: 'Manage trusted devices and 6-digit confirmation codes',
        group: 'Devices and backup',
        keywords: ['paired', 'devices', 'trusted', 'verify', 'connect', 'phone', 'laptop'],
        builder: (context, settings, colors) {
          final pairedCount = settings.getPairedDevices().length;
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PairedDevicesScreen()),
              );
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.devices_outlined, color: colors.gold, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Paired devices',
                          style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$pairedCount trusted device${pairedCount == 1 ? '' : 's'}',
                          style: appFont(color: colors.mute, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.mute, size: 20),
                ],
              ),
            ),
          );
        },
      ),
      SettingEntry(
        id: 'google_drive_backup',
        title: 'Google Drive',
        description: 'Sync backup database to your personal Google Drive AppData folder',
        group: 'Devices and backup',
        isAdvanced: true,
        keywords: ['google', 'drive', 'backup', 'cloud', 'appdata', 'sync'],
        builder: (context, settings, colors) {
          return _GoogleDriveInlineControl(colors: colors);
        },
      ),

      // ==========================================
      // GROUP 7: This computer (desktop only)
      // ==========================================
      SettingEntry(
        id: 'close_to_tray',
        title: 'Close to system tray',
        description: 'Keeps app running in the system tray when closing window',
        group: 'This computer',
        isDesktopOnly: true,
        keywords: ['tray', 'system tray', 'close', 'minimize', 'background', 'desktop'],
        builder: (context, settings, colors) {
          return SettingsSwitchRow(
            title: 'Close to system tray',
            subtitle: 'Keeps app running in the system tray when closing window',
            value: settings.closeToTray,
            onChanged: (val) => settings.setCloseToTray(val),
            colors: colors,
          );
        },
      ),
      SettingEntry(
        id: 'launch_at_startup',
        title: 'Launch at startup',
        description: 'Starts ThoughtHolder in background on Windows boot',
        group: 'This computer',
        isDesktopOnly: true,
        keywords: ['startup', 'boot', 'launch', 'autostart', 'windows', 'desktop'],
        builder: (context, settings, colors) {
          return SettingsSwitchRow(
            title: 'Launch at startup',
            subtitle: 'Starts ThoughtHolder in the background when your computer boots',
            value: settings.launchAtStartup,
            onChanged: (val) => DesktopManager.instance.toggleLaunchAtStartup(val),
            colors: colors,
          );
        },
      ),
      SettingEntry(
        id: 'speech_online',
        title: 'Online speech recognition (fallback mode)',
        description: 'Uses Windows speech recognition service when Whisper is offline',
        group: 'This computer',
        isAdvanced: true,
        isDesktopOnly: true,
        keywords: ['speech', 'online', 'recognition', 'windows', 'fallback', 'mic', 'microphone'],
        builder: (context, settings, colors) {
          return SettingsSwitchRow(
            title: 'Online speech recognition (fallback mode)',
            subtitle: 'Uses Windows speech recognition service when Whisper is offline',
            value: settings.speechOnline,
            onChanged: (val) => settings.setSpeechOnline(val),
            colors: colors,
          );
        },
      ),
      SettingEntry(
        id: 'global_hotkey',
        title: 'Global hotkey shortcut',
        description: 'Ctrl + Shift + B pops up capture window from any open window',
        group: 'This computer',
        isAdvanced: true,
        isDesktopOnly: true,
        keywords: ['hotkey', 'shortcut', 'ctrl', 'shift', 'b', 'keyboard', 'pop up'],
        builder: (context, settings, colors) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.keyboard, color: colors.gold, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Global hotkey shortcut',
                        style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.goldBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.gold),
                      ),
                      child: Text(
                        'Ctrl + Shift + B',
                        style: appFont(color: colors.gold, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Pops up the capture window immediately from any open window, ready to record your thought.',
                  style: appFont(color: colors.mute, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
      SettingEntry(
        id: 'windows_sound_setting',
        title: 'Windows sound and microphone',
        description: 'Adjust audio levels or microphone input in Windows settings',
        group: 'This computer',
        isAdvanced: true,
        isDesktopOnly: true,
        keywords: ['mic', 'microphone', 'sound', 'audio', 'windows', 'level', 'input', 'headset'],
        builder: (context, settings, colors) {
          return SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _openUri('ms-settings:sound'),
              icon: Icon(Icons.mic, size: 18, color: colors.gold),
              label: Text('Sound & microphone settings', style: appFont(color: colors.gold, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          );
        },
      ),
      SettingEntry(
        id: 'windows_speech_setting',
        title: 'Windows speech',
        description: 'Configure Windows system speech recognition settings',
        group: 'This computer',
        isAdvanced: true,
        isDesktopOnly: true,
        keywords: ['speech', 'voice', 'windows', 'system', 'recognition', 'mic'],
        builder: (context, settings, colors) {
          return SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _openUri('ms-settings:speech'),
              icon: Icon(Icons.settings_voice, size: 18, color: colors.gold),
              label: Text('Windows speech settings', style: appFont(color: colors.gold, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.line),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          );
        },
      ),
    ];
  }

  static Future<void> _openUri(String uriString) async {
    final uri = Uri.parse(uriString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Cannot launch $uriString: $e');
    }
  }

  static Widget _buildThemeOption(
    String label,
    String key,
    IconData icon,
    SettingsService settings,
    AppColors colors,
  ) {
    final isSelected = settings.theme == key;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => settings.setTheme(key),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.goldBg : colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? colors.gold : colors.line,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: isSelected ? colors.gold : colors.mute),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: appFont(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? colors.gold : colors.mute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSegmentedOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required AppColors colors,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.goldBg : colors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? colors.gold : colors.line,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colors.gold : colors.mute,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildSoundGroupRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required VoidCallback onTest,
    required AppColors colors,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: appFont(color: colors.mute, fontSize: 12, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: OutlinedButton(
              onPressed: onTest,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.line),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'Test',
                style: appFont(color: colors.gold, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value ? 'On' : 'Off',
            style: appFont(
              color: value ? colors.gold : colors.mute,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Switch(
            value: value,
            activeThumbColor: colors.gold,
            activeTrackColor: colors.goldBg,
            inactiveThumbColor: colors.mute,
            inactiveTrackColor: colors.line,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Interactive Inline Helper Widgets
// -------------------------------------------------------------

class _GroqKeyInlineControl extends StatefulWidget {
  final SettingsService settings;
  final AppColors colors;

  const _GroqKeyInlineControl({required this.settings, required this.colors});

  @override
  State<_GroqKeyInlineControl> createState() => _GroqKeyInlineControlState();
}

class _GroqKeyInlineControlState extends State<_GroqKeyInlineControl> {
  bool _editing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.groqApiKey);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatMasked(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'No key saved';
    if (t.length <= 8) return '••••••••';
    return '${t.substring(0, 4)}••••${t.substring(t.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final settings = widget.settings;

    if (!_editing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _formatMasked(settings.groqApiKey),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 14, letterSpacing: 1.2),
              ),
            ),
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: () => setState(() => _editing = true),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.gold),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text('Edit key', style: appFont(color: colors.gold, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            obscureText: true,
            style: appFont(color: colors.text, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'gsk_...',
              hintStyle: appFont(color: colors.mute),
              filled: true,
              fillColor: colors.bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.gold, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 38,
          child: ElevatedButton(
            onPressed: () {
              settings.setGroqApiKey(_controller.text.trim());
              setState(() => _editing = false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Save'),
          ),
        ),
      ],
    );
  }
}

class _TestConnectionInlineControl extends StatefulWidget {
  final SettingsService settings;
  final AppColors colors;

  const _TestConnectionInlineControl({required this.settings, required this.colors});

  @override
  State<_TestConnectionInlineControl> createState() => _TestConnectionInlineControlState();
}

class _TestConnectionInlineControlState extends State<_TestConnectionInlineControl> {
  bool _testing = false;
  String? _status;

  Future<void> _runTest() async {
    setState(() {
      _testing = true;
      _status = null;
    });

    final key = widget.settings.groqApiKey.trim();
    final reachable = await VoiceTranscriptionService().checkGroqReachability(key);

    if (mounted) {
      setState(() {
        _testing = false;
        _status = reachable
            ? '✓ Connected! Whisper Large V3 Turbo is online.'
            : '✗ Failed to reach Groq. Check API key & internet.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Row(
      children: [
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _testing ? null : _runTest,
            icon: _testing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.wifi_tethering, size: 16),
            label: Text(_testing ? 'Checking…' : 'Test connection'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.black,
              textStyle: appFont(fontWeight: FontWeight.bold, fontSize: 13),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (_status != null)
          Expanded(
            child: Text(
              _status!,
              style: appFont(
                color: _status!.startsWith('✓') ? colors.done : colors.bad,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

class _PromptPrimingInlineControl extends StatefulWidget {
  final SettingsService settings;
  final AppColors colors;

  const _PromptPrimingInlineControl({required this.settings, required this.colors});

  @override
  State<_PromptPrimingInlineControl> createState() => _PromptPrimingInlineControlState();
}

class _PromptPrimingInlineControlState extends State<_PromptPrimingInlineControl> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.whisperPrompt);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Names and terms', style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          'Primes Whisper so it accurately spells names like Albert, local towns, and technical jargon.',
          style: appFont(color: colors.mute, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          style: appFont(color: colors.text, fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'e.g. Albert, PK, Aaenics, Ghana...',
            hintStyle: appFont(color: colors.mute),
            filled: true,
            fillColor: colors.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.line)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: colors.gold, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: (val) => widget.settings.setWhisperPrompt(val),
        ),
      ],
    );
  }
}

class _GoogleDriveInlineControl extends StatefulWidget {
  final AppColors colors;

  const _GoogleDriveInlineControl({required this.colors});

  @override
  State<_GoogleDriveInlineControl> createState() => _GoogleDriveInlineControlState();
}

class _GoogleDriveInlineControlState extends State<_GoogleDriveInlineControl> {
  final GoogleDriveService _driveService = GoogleDriveService();
  bool _isSignedIn = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    try {
      final signed = await _driveService.isSignedIn;
      if (mounted) setState(() => _isSignedIn = signed);
    } catch (_) {}
  }

  Future<void> _signIn() async {
    try {
      final ok = await _driveService.signIn();
      if (mounted) setState(() => _isSignedIn = ok);
    } catch (_) {}
  }

  Future<void> _signOut() async {
    await _driveService.signOut();
    if (mounted) setState(() => _isSignedIn = false);
  }

  Future<void> _sync() async {
    setState(() => _isSyncing = true);
    try {
      await _driveService.syncThoughtsToDrive();
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync complete!')));
      }
    } catch (_) {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.cloud_done, color: _isSignedIn ? colors.done : colors.mute, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Google Drive status', style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      _isSignedIn ? 'Connected' : 'Not connected',
                      style: appFont(color: _isSignedIn ? colors.done : colors.mute, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (_isSignedIn)
                TextButton(
                  onPressed: _signOut,
                  child: Text('Disconnect', style: appFont(color: colors.bad, fontWeight: FontWeight.bold, fontSize: 13)),
                )
              else
                ElevatedButton(
                  onPressed: _signIn,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Connect'),
                ),
            ],
          ),
          if (_isSignedIn) ...[
            const SizedBox(height: 12),
            Divider(color: colors.line, height: 1),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _isSyncing ? null : _sync,
                icon: _isSyncing
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: colors.gold))
                    : Icon(Icons.sync, size: 18, color: colors.gold),
                label: Text(
                  _isSyncing ? 'Syncing…' : 'Force sync now',
                  style: appFont(color: colors.gold, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.gold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
