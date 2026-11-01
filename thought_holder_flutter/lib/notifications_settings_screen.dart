import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'notification_service.dart';
import 'settings_service.dart';

class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});

  @override
  State<NotificationsSettingsScreen> createState() =>
      _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState
    extends State<NotificationsSettingsScreen> {
  Future<bool> _ensureNotificationPermission(
      BuildContext context, AppColors colors) async {
    if (!kIsWeb && Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        final result = await Permission.notification.request();
        if (!result.isGranted) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Notifications are disabled. Turn them on in system settings to receive reminders.',
                  style: appFont(color: colors.text),
                ),
                backgroundColor: colors.card,
                action: SnackBarAction(
                  label: 'Settings',
                  textColor: colors.gold,
                  onPressed: () => openAppSettings(),
                ),
              ),
            );
          }
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _pickTime({
    required BuildContext context,
    required String initialTimeStr,
    required ValueChanged<String> onSelected,
  }) async {
    final parts = initialTimeStr.split(':');
    final initialTime = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );

    if (picked != null) {
      final hourStr = picked.hour.toString().padLeft(2, '0');
      final minuteStr = picked.minute.toString().padLeft(2, '0');
      onSelected('$hourStr:$minuteStr');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final notificationService = context.read<NotificationService>();
    final colors = AppColors.of(settings.theme);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: colors.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notifications',
          style: appFont(
            color: colors.gold,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // Row 1: Capture button in notifications
          _buildRowCard(
            colors: colors,
            icon: Icons.touch_app_outlined,
            title: 'Capture button in notifications',
            subtitle:
                'Keep a silent button in your notifications to quickly capture thoughts anytime.',
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    settings.quickCaptureNotification ? 'On' : 'Off',
                    style: appFont(
                      color: settings.quickCaptureNotification
                          ? colors.gold
                          : colors.mute,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Switch(
                    value: settings.quickCaptureNotification,
                    activeThumbColor: colors.gold,
                    onChanged: (val) async {
                      if (val) {
                        final ok = await _ensureNotificationPermission(context, colors);
                        if (!ok) return;
                      }
                      await settings.setQuickCaptureNotification(val);
                      await notificationService.syncQuickCaptureNotification();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Row 2: Start here nudges
          _buildRowCard(
            colors: colors,
            icon: Icons.star_outline,
            title: 'Start here nudges',
            subtitle:
                'Get a friendly suggestion for your top-ranked priority idea at predictable times.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Remind me what to start with',
                  style: appFont(
                      color: colors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFrequencyChip('Off', 'off', settings.startHereFrequency,
                        (f) => settings.setStartHereFrequency(f), colors),
                    _buildFrequencyChip('Once a day', 'once',
                        settings.startHereFrequency,
                        (f) async {
                          final ok = await _ensureNotificationPermission(context, colors);
                          if (ok) await settings.setStartHereFrequency(f);
                        }, colors),
                    _buildFrequencyChip('2 times a day', 'twice',
                        settings.startHereFrequency,
                        (f) async {
                          final ok = await _ensureNotificationPermission(context, colors);
                          if (ok) await settings.setStartHereFrequency(f);
                        }, colors),
                    _buildFrequencyChip('3 times a day', 'thrice',
                        settings.startHereFrequency,
                        (f) async {
                          final ok = await _ensureNotificationPermission(context, colors);
                          if (ok) await settings.setStartHereFrequency(f);
                        }, colors),
                  ],
                ),
                if (settings.startHereFrequency != 'off') ...[
                  const SizedBox(height: 16),
                  Text(
                    'Exact reminder times',
                    style: appFont(color: colors.mute, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _buildTimesEditor(
                    context: context,
                    frequency: settings.startHereFrequency,
                    times: settings.startHereTimes,
                    colors: colors,
                    onTimesUpdated: (times) =>
                        settings.setStartHereTimes(times),
                  ),
                  const Divider(height: 24),
                  // Lock-screen privacy toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Show idea’s words on lock screen',
                              style: appFont(
                                  color: colors.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'When off, lock screen shows only "Your next step is ready".',
                              style: appFont(color: colors.mute, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: settings.showWordsOnLockScreen,
                        activeThumbColor: colors.gold,
                        onChanged: (val) =>
                            settings.setShowWordsOnLockScreen(val),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  // Tap target setting
                  Text(
                    'When I tap a Start here nudge, open:',
                    style: appFont(
                        color: colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildChoiceChip(
                          label: 'The idea',
                          isSelected: settings.startHereTapTarget == 'idea',
                          onTap: () => settings.setStartHereTapTarget('idea'),
                          colors: colors,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildChoiceChip(
                          label: 'Capture',
                          isSelected: settings.startHereTapTarget == 'capture',
                          onTap: () => settings.setStartHereTapTarget('capture'),
                          colors: colors,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Row 3: Capture reminders
          _buildRowCard(
            colors: colors,
            icon: Icons.edit_notifications_outlined,
            title: 'Capture reminders',
            subtitle:
                'A gentle prompt ("Got a thought? Tap to capture.") to help you clear mental clutter.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Remind me to capture thoughts',
                  style: appFont(
                      color: colors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildFrequencyChip('Off', 'off',
                        settings.captureReminderFrequency,
                        (f) => settings.setCaptureReminderFrequency(f), colors),
                    _buildFrequencyChip('Once a day', 'once',
                        settings.captureReminderFrequency,
                        (f) async {
                          final ok = await _ensureNotificationPermission(context, colors);
                          if (ok) await settings.setCaptureReminderFrequency(f);
                        }, colors),
                    _buildFrequencyChip('2 times a day', 'twice',
                        settings.captureReminderFrequency,
                        (f) async {
                          final ok = await _ensureNotificationPermission(context, colors);
                          if (ok) await settings.setCaptureReminderFrequency(f);
                        }, colors),
                    _buildFrequencyChip('3 times a day', 'thrice',
                        settings.captureReminderFrequency,
                        (f) async {
                          final ok = await _ensureNotificationPermission(context, colors);
                          if (ok) await settings.setCaptureReminderFrequency(f);
                        }, colors),
                  ],
                ),
                if (settings.captureReminderFrequency != 'off') ...[
                  const SizedBox(height: 16),
                  Text(
                    'Exact reminder times',
                    style: appFont(color: colors.mute, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  _buildTimesEditor(
                    context: context,
                    frequency: settings.captureReminderFrequency,
                    times: settings.captureReminderTimes,
                    colors: colors,
                    onTimesUpdated: (times) =>
                        settings.setCaptureReminderTimes(times),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Row 4: Recording notification
          _buildRowCard(
            colors: colors,
            icon: Icons.mic_outlined,
            title: 'Recording notification',
            subtitle:
                'Always active while recording so you can see the running timer and stop anytime. Cannot be turned off.',
            child: Container(
              height: 48,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: colors.mute),
                  const SizedBox(width: 8),
                  Text(
                    'Always enabled during voice recording',
                    style: appFont(
                      color: colors.mute,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Shared Quiet Hours Row
          _buildRowCard(
            colors: colors,
            icon: Icons.nightlight_round_outlined,
            title: 'Quiet hours',
            subtitle:
                'No notifications or nudges will be sent during these hours.',
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(
                      context: context,
                      initialTimeStr: settings.quietHoursStart,
                      onSelected: (time) =>
                          settings.setQuietHours(time, settings.quietHoursEnd),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.line),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('From', style: appFont(color: colors.mute, fontSize: 13)),
                          Text(settings.quietHoursStart,
                              style: appFont(
                                  color: colors.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickTime(
                      context: context,
                      initialTimeStr: settings.quietHoursEnd,
                      onSelected: (time) => settings.setQuietHours(
                          settings.quietHoursStart, time),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.line),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('To', style: appFont(color: colors.mute, fontSize: 13)),
                          Text(settings.quietHoursEnd,
                              style: appFont(
                                  color: colors.gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // "Send me a test" button
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await _ensureNotificationPermission(context, colors);
                if (!ok) return;
                final msg = await notificationService.sendTestNotifications();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        msg,
                        style: appFont(color: colors.text),
                      ),
                      backgroundColor: colors.card,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              },
              icon: Icon(Icons.send_outlined, color: colors.gold, size: 18),
              label: Text(
                'Send me a test',
                style: appFont(
                  color: colors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.gold, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildRowCard({
    required AppColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.gold, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: appFont(
                  color: colors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: appFont(color: colors.mute, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildFrequencyChip(
    String label,
    String key,
    String current,
    ValueChanged<String> onSelected,
    AppColors colors,
  ) {
    final isSelected = current == key;
    return InkWell(
      onTap: () => onSelected(key),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? colors.goldBg : colors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? colors.gold : colors.line,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: appFont(
            color: isSelected ? colors.gold : colors.mute,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required AppColors colors,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? colors.goldBg : colors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? colors.gold : colors.line,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: appFont(
            color: isSelected ? colors.gold : colors.mute,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildTimesEditor({
    required BuildContext context,
    required String frequency,
    required List<String> times,
    required AppColors colors,
    required ValueChanged<List<String>> onTimesUpdated,
  }) {
    final count = frequency == 'once'
        ? 1
        : frequency == 'twice'
            ? 2
            : 3;
    final currentTimes = List<String>.from(times);
    while (currentTimes.length < count) {
      currentTimes.add('12:00');
    }

    return Row(
      children: List.generate(count, (index) {
        final timeStr = currentTimes[index];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < count - 1 ? 8.0 : 0.0),
            child: InkWell(
              onTap: () => _pickTime(
                context: context,
                initialTimeStr: timeStr,
                onSelected: (newTime) {
                  currentTimes[index] = newTime;
                  onTimesUpdated(currentTimes);
                },
              ),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.line),
                ),
                alignment: Alignment.center,
                child: Text(
                  timeStr,
                  style: appFont(
                    color: colors.gold,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
