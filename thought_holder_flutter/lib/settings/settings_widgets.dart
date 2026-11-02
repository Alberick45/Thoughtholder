import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Reusable switch tile with visible "On" / "Off" text and >= 48px target height.
class SettingsSwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final AppColors colors;

  const SettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: appFont(
                    color: colors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: appFont(color: colors.mute, fontSize: 12, height: 1.3),
                  ),
                ],
              ],
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

/// 52px expandable text button at the bottom of a group's card
class ShowMoreButton extends StatelessWidget {
  final int count;
  final bool isExpanded;
  final VoidCallback onTap;
  final AppColors colors;

  const ShowMoreButton({
    super.key,
    required this.count,
    required this.isExpanded,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(
          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: colors.gold,
          size: 20,
        ),
        label: Text(
          isExpanded ? 'Show fewer options' : 'Show more options ($count)',
          style: appFont(
            color: colors.gold,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
