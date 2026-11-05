import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import 'group_page_scaffold.dart';
import 'settings_widgets.dart';

class GesturesGroupScreen extends StatelessWidget {
  const GesturesGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GroupPageScaffold(
      title: 'Gestures',
      child: GesturesGroupContent(),
    );
  }
}

class GesturesGroupContent extends StatelessWidget {
  const GesturesGroupContent({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Swipe between Sorted and Unsorted
        SettingsSwitchRow(
          title: 'Swipe between Sorted and Unsorted',
          subtitle: 'Swipe left or right to switch between Sorted and Unsorted tabs.',
          value: settings.swipeSortedUnsorted,
          onChanged: (val) => settings.setSwipeSortedUnsorted(val),
          colors: colors,
        ),
        Divider(color: colors.line, height: 24),

        // 2. Swipe between Capture and Stream
        SettingsSwitchRow(
          title: 'Swipe between Capture and Stream',
          subtitle: 'Swipe left or right to move between Capture and Stream.',
          value: settings.swipeCaptureStream,
          onChanged: (val) => settings.setSwipeCaptureStream(val),
          colors: colors,
        ),
        Divider(color: colors.line, height: 24),

        // 3. Swipe actions on ideas
        SettingsSwitchRow(
          title: 'Swipe actions on ideas',
          subtitle:
              'Swiping on a card does an action, so change tabs from the tab pills or the header instead.',
          value: settings.swipeActionsOnIdeas,
          onChanged: (val) => settings.setSwipeActionsOnIdeas(val),
          colors: colors,
        ),
        Divider(color: colors.line, height: 24),

        // 4. Swipe distance
        Text(
          'Swipe distance',
          style: appFont(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'How far across the screen you drag before the tab changes.',
          style: appFont(color: colors.mute, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildDistanceOption('Easy (20%)', 'Easy', settings, colors),
            const SizedBox(width: 8),
            _buildDistanceOption('Normal (30%)', 'Normal', settings, colors),
            const SizedBox(width: 8),
            _buildDistanceOption('Firm (45%)', 'Firm', settings, colors),
          ],
        ),
      ],
    );
  }

  Widget _buildDistanceOption(
    String label,
    String key,
    SettingsService settings,
    AppColors colors,
  ) {
    final isSelected = settings.swipeDistance == key;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => settings.setSwipeDistance(key),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.goldBg : colors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? colors.gold : colors.line,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: appFont(
              color: isSelected ? colors.gold : colors.text,
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

