import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import 'group_page_scaffold.dart';

class LookGroupScreen extends StatelessWidget {
  const LookGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GroupPageScaffold(
      title: 'Look and feel',
      child: LookGroupContent(),
    );
  }
}

class LookGroupContent extends StatelessWidget {
  const LookGroupContent({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Theme',
          style: appFont(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose the interface appearance for ThoughtHolder.',
          style: appFont(color: colors.mute, fontSize: 13),
        ),
        const SizedBox(height: 14),
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
  }

  Widget _buildThemeOption(
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
}
