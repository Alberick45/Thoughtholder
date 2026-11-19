import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../thought_provider.dart';
import '../desktop_manager.dart';
import '../google_drive_service.dart';
import 'look_group.dart';
import 'ideas_group.dart';
import 'voice_group.dart';
import 'sounds_group.dart';
import 'notifications_group.dart';
import 'devices_group.dart';
import 'computer_group.dart';
import 'gestures_group.dart';
import '../widgets/keyboard_safe_sheet.dart';
import 'diagnostics_screen.dart';
import 'settings_registry.dart';
import 'updates_group.dart';

class SettingsMenuScreen extends StatefulWidget {
  const SettingsMenuScreen({super.key});

  @override
  State<SettingsMenuScreen> createState() => _SettingsMenuScreenState();
}

class _SettingsMenuScreenState extends State<SettingsMenuScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GoogleDriveService _driveService = GoogleDriveService();
  bool _driveSignedIn = false;
  Timer? _debounceTimer;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _checkDriveStatus();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkDriveStatus() async {
    try {
      final signedIn = await _driveService.isSignedIn;
      if (mounted) {
        setState(() {
          _driveSignedIn = signedIn;
        });
      }
    } catch (_) {}
  }

  String _getThemeSummary(String theme) {
    switch (theme) {
      case 'light':
        return 'Soft light theme';
      case 'calm':
        return 'Calm theme';
      default:
        return 'Dark theme';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final thoughtProvider = context.watch<ThoughtProvider>();
    final colors = AppColors.of(settings.theme);
    final isDesktop = DesktopManager.isDesktop;

    // Live summaries
    final lookSummary = _getThemeSummary(settings.theme);
    final bucketsCount = thoughtProvider.buckets.length;
    final unsortedOrder = settings.unsortedOrder == 'oldest' ? 'oldest' : 'newest';
    final ideasSummary = '$bucketsCount buckets · $unsortedOrder first';
    final voiceSummary = settings.groqApiKey.trim().isNotEmpty
        ? 'Groq key saved'
        : 'Groq not set up yet';
    final soundsSummary = settings.soundsEnabled
        ? 'On · volume ${(settings.soundVolume * 100).round()}%'
        : 'Off';
    const notificationsSummary = 'Start here nudges and reminders';
    final pairedCount = settings.getPairedDevices().length;
    final driveStatus = _driveSignedIn ? 'connected' : 'not connected';
    final devicesSummary = '$pairedCount paired devices · Google Drive $driveStatus';
    final gesturesTabs = (settings.swipeSortedUnsorted || settings.swipeCaptureStream)
        ? 'Tab swipe on'
        : 'Tab swipe off';
    final gesturesCards = settings.swipeActionsOnIdeas ? 'card actions on' : 'card actions off';
    final gesturesSummary = '$gesturesTabs · $gesturesCards';
    final trayStatus = settings.closeToTray ? 'on' : 'off';
    final startupStatus = settings.launchAtStartup ? 'on' : 'off';
    final computerSummary = 'Tray $trayStatus · startup $startupStatus';

    return KeyboardSafeSheet(
      openingHeight: MediaQuery.of(context).size.height * 0.94,
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      backgroundColor: colors.bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header: Plain "Settings" title with close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Settings',
                style: appFont(
                  color: colors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: colors.mute, size: 24),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close settings',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Search bar directly under header
          SizedBox(
            height: 52,
            child: TextField(
              controller: _searchController,
              style: appFont(color: colors.text, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search settings',
                hintStyle: appFont(color: colors.mute, fontSize: 15),
                prefixIcon: Icon(Icons.search, color: colors.gold, size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: colors.mute, size: 18),
                        onPressed: () {
                          _debounceTimer?.cancel();
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: colors.card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.gold, width: 1.5),
                ),
              ),
              onChanged: (text) {
                _debounceTimer?.cancel();
                if (text.trim().isEmpty) {
                  setState(() {
                    _searchQuery = '';
                  });
                } else {
                  _debounceTimer = Timer(const Duration(milliseconds: 150), () {
                    if (mounted) {
                      setState(() {
                        _searchQuery = text.trim();
                      });
                    }
                  });
                  setState(() {});
                }
              },
            ),
          ),
          const SizedBox(height: 16),

          // 3. Menu Rows or Search Results
          Expanded(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResults(context, settings, colors, isDesktop)
                : _buildMenuRows(
                    context,
                    colors,
                    isDesktop,
                    lookSummary,
                    ideasSummary,
                    voiceSummary,
                    soundsSummary,
                    notificationsSummary,
                    devicesSummary,
                    gesturesSummary,
                    computerSummary,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    SettingsService settings,
    AppColors colors,
    bool isDesktop,
  ) {
    final allEntries = SettingsRegistry.getEntries();
    final matchingEntries = allEntries.where((entry) {
      if (entry.isDesktopOnly && !isDesktop) return false;
      return entry.matches(_searchQuery);
    }).toList();

    if (matchingEntries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 44, color: colors.mute),
              const SizedBox(height: 14),
              Text(
                'No settings match. Try another word.',
                textAlign: TextAlign.center,
                style: appFont(
                  color: colors.mute,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    const groupsOrder = [
      'Look and feel',
      'Ideas and buckets',
      'Voice and AI',
      'Sounds',
      'Notifications',
      'Devices and backup',
      'Gestures',
      'This computer',
    ];

    final Map<String, List<SettingEntry>> grouped = {};
    for (final entry in matchingEntries) {
      grouped.putIfAbsent(entry.group, () => []).add(entry);
    }

    return ListView(
      controller: _scrollController,
      children: [
        for (final groupName in groupsOrder)
          if (grouped.containsKey(groupName) && grouped[groupName]!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 8, left: 4),
              child: Text(
                groupName.toUpperCase(),
                style: appFont(
                  color: colors.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < grouped[groupName]!.length; i++) ...[
                    if (i > 0) Divider(color: colors.line, height: 24),
                    grouped[groupName]![i].builder(context, settings, colors),
                  ],
                ],
              ),
            ),
          ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMenuRows(
    BuildContext context,
    AppColors colors,
    bool isDesktop,
    String lookSummary,
    String ideasSummary,
    String voiceSummary,
    String soundsSummary,
    String notificationsSummary,
    String devicesSummary,
    String gesturesSummary,
    String computerSummary,
  ) {
    return ListView(
      controller: _scrollController,
      children: [
        // 1. Look and feel
        _buildMenuRow(
          icon: Icons.palette_outlined,
          title: 'Look and feel',
          summary: lookSummary,
          colors: colors,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LookGroupScreen()),
            );
          },
        ),
        const SizedBox(height: 10),

        // 2. Ideas and buckets
        _buildMenuRow(
          icon: Icons.folder_outlined,
          title: 'Ideas and buckets',
          summary: ideasSummary,
          colors: colors,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IdeasGroupScreen()),
            );
          },
        ),
        const SizedBox(height: 10),

        // 3. Voice and AI
        _buildMenuRow(
          icon: Icons.mic_none_outlined,
          title: 'Voice and AI',
          summary: voiceSummary,
          colors: colors,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VoiceGroupScreen()),
            );
          },
        ),
        const SizedBox(height: 10),

        // 4. Sounds
        _buildMenuRow(
          icon: Icons.volume_up_outlined,
          title: 'Sounds',
          summary: soundsSummary,
          colors: colors,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SoundsGroupScreen()),
            );
          },
        ),
        const SizedBox(height: 10),

        // 5. Notifications
        _buildMenuRow(
          icon: Icons.notifications_none_outlined,
          title: 'Notifications',
          summary: notificationsSummary,
          colors: colors,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsGroupScreen()),
            );
          },
        ),
        const SizedBox(height: 10),

        // 6. Devices and backup
        _buildMenuRow(
          icon: Icons.devices_outlined,
          title: 'Devices and backup',
          summary: devicesSummary,
          colors: colors,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DevicesGroupScreen()),
            );
          },
        ),
        const SizedBox(height: 10),

        // 7. Gestures
        _buildMenuRow(
          icon: Icons.swipe_outlined,
          title: 'Gestures',
          summary: gesturesSummary,
          colors: colors,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GesturesGroupScreen()),
            );
          },
        ),

        // 8. This computer (Windows and desktop builds ONLY)
        if (isDesktop) ...[
          const SizedBox(height: 10),
          _buildMenuRow(
            icon: Icons.desktop_windows_outlined,
            title: 'This computer',
            summary: computerSummary,
            colors: colors,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ComputerGroupScreen()),
              );
            },
          ),
        ],

        // 9. Diagnostics
        const SizedBox(height: 10),
        _buildMenuRow(
          icon: Icons.health_and_safety_outlined,
          title: 'Diagnostics',
          summary: 'Database health, backups, and self-checks',
          colors: colors,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            );
          },
        ),
        const SizedBox(height: 10),

        // 10. Updates & data safety
        _buildMenuRow(
          icon: Icons.system_update_outlined,
          title: 'Updates and safety',
          summary: 'Check for updates, beta channel, and backups',
          colors: colors,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UpdatesGroupScreen()),
            );
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMenuRow({
    required IconData icon,
    required String title,
    required String summary,
    required AppColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.line),
        ),
        child: Row(
          children: [
            // 44px rounded icon square (gold on soft gold background)
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.goldBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.gold.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: colors.gold, size: 22),
            ),
            const SizedBox(width: 16),

            // Title and live one-line summary
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: appFont(
                      color: colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      color: colors.mute,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Chevron
            Icon(Icons.chevron_right, color: colors.mute, size: 22),
          ],
        ),
      ),
    );
  }
}
