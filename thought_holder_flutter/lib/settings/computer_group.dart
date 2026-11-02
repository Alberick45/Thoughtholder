import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../desktop_manager.dart';
import 'group_page_scaffold.dart';
import 'settings_state.dart';
import 'settings_widgets.dart';

class ComputerGroupScreen extends StatelessWidget {
  const ComputerGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GroupPageScaffold(
      title: 'This computer',
      child: ComputerGroupContent(),
    );
  }
}

class ComputerGroupContent extends StatefulWidget {
  const ComputerGroupContent({super.key});

  @override
  State<ComputerGroupContent> createState() => _ComputerGroupContentState();
}

class _ComputerGroupContentState extends State<ComputerGroupContent> {
  static const String _groupId = 'computer_group';

  Future<void> _openWindowsSetting(String uriString) async {
    final uri = Uri.parse(uriString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Cannot launch $uriString: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final isExpanded = SettingsState.isExpanded(_groupId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Close to system tray
        SettingsSwitchRow(
          title: 'Close to system tray',
          subtitle: 'Keeps app running in the system tray when closing window',
          value: settings.closeToTray,
          onChanged: (val) async {
            await settings.setCloseToTray(val);
            if (mounted) setState(() {});
          },
          colors: colors,
        ),

        const SizedBox(height: 12),
        Divider(color: colors.line, height: 1),
        const SizedBox(height: 12),

        // 2. Launch at startup
        SettingsSwitchRow(
          title: 'Launch at startup',
          subtitle: 'Starts ThoughtHolder in the background when your computer boots',
          value: settings.launchAtStartup,
          onChanged: (val) async {
            await DesktopManager.instance.toggleLaunchAtStartup(val);
            if (mounted) setState(() {});
          },
          colors: colors,
        ),

        // 3. Collapsible options (under "Show more options")
        if (isExpanded) ...[
          const SizedBox(height: 20),
          Divider(color: colors.line, height: 1),
          const SizedBox(height: 16),

          // Online speech recognition fallback
          SettingsSwitchRow(
            title: 'Online speech recognition (fallback mode)',
            subtitle: 'Uses Windows speech recognition service when Whisper is offline',
            value: settings.speechOnline,
            onChanged: (val) async {
              await settings.setSpeechOnline(val);
              if (mounted) setState(() {});
            },
            colors: colors,
          ),

          const SizedBox(height: 16),
          Divider(color: colors.line, height: 1),
          const SizedBox(height: 16),

          // Global Hotkey shortcut note
          Container(
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
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
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
                        style: appFont(
                          color: colors.gold,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
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
          ),

          const SizedBox(height: 16),
          Divider(color: colors.line, height: 1),
          const SizedBox(height: 16),

          // Windows audio settings buttons
          Text(
            'Windows system settings',
            style: appFont(
              color: colors.text,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adjust audio levels or configure speech recognition in Windows settings.',
            style: appFont(color: colors.mute, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _openWindowsSetting('ms-settings:sound'),
                    icon: Icon(Icons.mic, size: 16, color: colors.gold),
                    label: Text(
                      'Sound & microphone',
                      style: appFont(color: colors.gold, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () => _openWindowsSetting('ms-settings:speech'),
                    icon: Icon(Icons.settings_voice, size: 16, color: colors.gold),
                    label: Text(
                      'Windows speech',
                      style: appFont(color: colors.gold, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 12),
        ShowMoreButton(
          count: 3,
          isExpanded: isExpanded,
          onTap: () {
            setState(() {
              SettingsState.toggleExpanded(_groupId);
            });
          },
          colors: colors,
        ),
      ],
    );
  }
}
