import 'package:flutter/material.dart';
import 'settings/settings_menu.dart';

export 'settings/settings_menu.dart';
export 'settings/look_group.dart';
export 'settings/ideas_group.dart';
export 'settings/voice_group.dart';
export 'settings/sounds_group.dart';
export 'settings/notifications_group.dart';
export 'settings/devices_group.dart';
export 'settings/computer_group.dart';

class SettingsModal extends StatelessWidget {
  const SettingsModal({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsMenuScreen();
  }
}
