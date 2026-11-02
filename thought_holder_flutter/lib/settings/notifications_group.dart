import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../notifications_settings_screen.dart';
import 'group_page_scaffold.dart';

class NotificationsGroupScreen extends StatelessWidget {
  const NotificationsGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GroupPageScaffold(
      title: 'Notifications',
      child: NotificationsGroupContent(),
    );
  }
}

class NotificationsGroupContent extends StatelessWidget {
  const NotificationsGroupContent({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notifications & reminders',
          style: appFont(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Configure Start here nudges, gentle capture reminders, and quiet hours.',
          style: appFont(color: colors.mute, fontSize: 13),
        ),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationsSettingsScreen(),
              ),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: colors.gold,
                  size: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications and reminders',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Start here nudges, capture reminders & quiet hours',
                        style: appFont(color: colors.mute, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.mute, size: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
