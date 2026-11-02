import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../sound_service.dart';
import 'group_page_scaffold.dart';
import 'settings_state.dart';
import 'settings_widgets.dart';

class SoundsGroupScreen extends StatelessWidget {
  const SoundsGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GroupPageScaffold(
      title: 'Sounds',
      child: SoundsGroupContent(),
    );
  }
}

class SoundsGroupContent extends StatefulWidget {
  const SoundsGroupContent({super.key});

  @override
  State<SoundsGroupContent> createState() => _SoundsGroupContentState();
}

class _SoundsGroupContentState extends State<SoundsGroupContent> {
  static const String _groupId = 'sounds_group';

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final soundsOn = settings.soundsEnabled;
    final vol = settings.soundVolume;
    final volPct = (vol * 100).round();
    final isExpanded = SettingsState.isExpanded(_groupId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Master Switch
        SettingsSwitchRow(
          title: 'Sounds',
          subtitle: 'Play soft feedback sounds for buttons and actions',
          value: soundsOn,
          onChanged: (val) async {
            await settings.setSoundsEnabled(val);
            await settings.setSoundPromptAnswered(true);
            if (val) {
              SoundService.instance.play(SoundEvent.switchOn, settings: settings, preview: true);
            }
            if (mounted) setState(() {});
          },
          colors: colors,
        ),

        if (soundsOn) ...[
          const SizedBox(height: 16),
          Divider(color: colors.line, height: 1),
          const SizedBox(height: 16),

          // 2. Volume slider: default 40%, capped at 80% maximum
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Volume',
                style: appFont(
                  color: colors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                '$volPct%',
                style: appFont(
                  color: colors.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
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
              max: 0.80, // Maximum 80% of full volume so nothing can be loud
              divisions: 16,
              onChanged: (val) async {
                await settings.setSoundVolume(val);
                if (mounted) setState(() {});
              },
              onChangeEnd: (val) {
                SoundService.instance.play(SoundEvent.save, settings: settings, preview: true);
              },
            ),
          ),

          const SizedBox(height: 16),
          Divider(color: colors.line, height: 1),
          const SizedBox(height: 16),

          // 3. Sound style selector
          Text(
            'Sound style',
            style: appFont(
              color: colors.text,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () async {
                      await settings.setSoundStyle('soft');
                      SoundService.instance.play(SoundEvent.save, settings: settings, preview: true);
                      if (mounted) setState(() {});
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: settings.soundStyle == 'soft'
                          ? colors.goldBg
                          : colors.bg,
                      side: BorderSide(
                        color: settings.soundStyle == 'soft' ? colors.gold : colors.line,
                        width: settings.soundStyle == 'soft' ? 1.8 : 1.0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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
                      if (mounted) setState(() {});
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: settings.soundStyle == 'crisp'
                          ? colors.goldBg
                          : colors.bg,
                      side: BorderSide(
                        color: settings.soundStyle == 'crisp' ? colors.gold : colors.line,
                        width: settings.soundStyle == 'crisp' ? 1.8 : 1.0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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

          // 4. Collapsible Group switches (under "Show more options")
          if (isExpanded) ...[
            const SizedBox(height: 20),
            Divider(color: colors.line, height: 1),
            const SizedBox(height: 14),

            _buildSoundGroupRow(
              title: 'Taps and buttons',
              subtitle: 'Button presses, tab switches, and popups',
              value: settings.soundGroupTaps,
              onChanged: (v) async {
                await settings.setSoundGroupTaps(v);
                if (mounted) setState(() {});
              },
              onTest: () => SoundService.instance.play(SoundEvent.tap, settings: settings, preview: true),
              colors: colors,
            ),
            Divider(color: colors.line, height: 16),

            _buildSoundGroupRow(
              title: 'Swipes and slides',
              subtitle: 'Tab swiping, bucket slider, and card swipe',
              value: settings.soundGroupSwipes,
              onChanged: (v) async {
                await settings.setSoundGroupSwipes(v);
                if (mounted) setState(() {});
              },
              onTest: () => SoundService.instance.play(SoundEvent.swipe, settings: settings, preview: true),
              colors: colors,
            ),
            Divider(color: colors.line, height: 16),

            _buildSoundGroupRow(
              title: 'Saving and finishing',
              subtitle: 'Saving thoughts, filing into buckets, and marking done',
              value: settings.soundGroupSaving,
              onChanged: (v) async {
                await settings.setSoundGroupSaving(v);
                if (mounted) setState(() {});
              },
              onTest: () => SoundService.instance.play(SoundEvent.done, settings: settings, preview: true),
              colors: colors,
            ),
            Divider(color: colors.line, height: 16),

            _buildSoundGroupRow(
              title: 'Deleting and warnings',
              subtitle: 'Move to trash, delete forever, undo, and error alerts',
              value: settings.soundGroupDeleting,
              onChanged: (v) async {
                await settings.setSoundGroupDeleting(v);
                if (mounted) setState(() {});
              },
              onTest: () => SoundService.instance.play(SoundEvent.trash, settings: settings, preview: true),
              colors: colors,
            ),
            Divider(color: colors.line, height: 16),

            _buildSoundGroupRow(
              title: 'Typing',
              subtitle: 'Plays a very soft sound for each key. Some people find this distracting.',
              value: settings.soundGroupTyping,
              onChanged: (v) async {
                await settings.setSoundGroupTyping(v);
                if (mounted) setState(() {});
              },
              onTest: () => SoundService.instance.play(SoundEvent.key, settings: settings, preview: true),
              colors: colors,
            ),
          ],

          const SizedBox(height: 12),
          ShowMoreButton(
            count: 5,
            isExpanded: isExpanded,
            onTap: () {
              setState(() {
                SettingsState.toggleExpanded(_groupId);
              });
            },
            colors: colors,
          ),
        ],
      ],
    );
  }

  Widget _buildSoundGroupRow({
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
                  style: appFont(
                    color: colors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
