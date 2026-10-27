import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'record_trigger.dart';
import 'settings_service.dart';

/// Manages desktop-specific integrations:
/// 1. System Tray icon & background daemon behavior
/// 2. Global Hotkey (Ctrl+Shift+B) to summon capture widget & record immediately
/// 3. Window Manager (minimize/close to tray, always-on-top popup)
/// 4. Launch at Windows Startup
class DesktopManager with WindowListener, TrayListener {
  static final DesktopManager instance = DesktopManager._();
  DesktopManager._();

  SettingsService? _settingsService;
  bool _initialized = false;
  String _trayIconPath = '';

  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  Future<void> init(SettingsService settingsService) async {
    if (!isDesktop || _initialized) return;
    _settingsService = settingsService;
    _initialized = true;

    try {
      // 1. Initialize Window Manager
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1100, 720),
        minimumSize: Size(480, 560),
        center: true,
        backgroundColor: Color(0xFF0E0E10),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'ThoughtHolder',
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setPreventClose(true);
        try {
          final iconPath = await _resolveIconPath();
          if (iconPath.isNotEmpty) {
            await windowManager.setIcon(iconPath);
          }
        } catch (_) {}
        await windowManager.show();
        await windowManager.focus();
      });
      windowManager.addListener(this);

      // 2. Initialize Launch at Startup
      launchAtStartup.setup(
        appName: 'ThoughtHolder',
        appPath: Platform.resolvedExecutable,
        packageName: 'com.example.thoughtholder',
      );

      // Synchronize with stored setting if previously set
      if (_settingsService?.launchAtStartup == true) {
        final isEnabled = await launchAtStartup.isEnabled();
        if (!isEnabled) {
          await launchAtStartup.enable();
        }
      }

      // 3. Initialize System Tray
      await _initSystemTray();

      // 4. Initialize Global Hotkey (Ctrl + Shift + B)
      await _initGlobalHotKey();
    } catch (e) {
      debugPrint('[DesktopManager] Init warning: $e');
    }
  }

  Future<void> _initSystemTray() async {
    try {
      trayManager.addListener(this);

      // Prepare tray icon path
      _trayIconPath = await _resolveIconPath();
      if (_trayIconPath.isNotEmpty) {
        await trayManager.setIcon(_trayIconPath);
      }
      await trayManager.setToolTip('ThoughtHolder - Brain Dump (Ctrl+Shift+B)');
      await updateContextMenu();
    } catch (e) {
      debugPrint('[DesktopManager] Tray init warning: $e');
    }
  }

  Future<String> _resolveIconPath() async {
    try {
      // If runner resource exists directly (dev mode)
      final localDev = File('windows/runner/resources/app_icon.ico');
      if (await localDev.exists()) {
        return localDev.absolute.path;
      }

      // Check adjacent to executable (packaged release)
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final exeIcon = File('$exeDir/data/flutter_assets/assets/app_icon.ico');
      if (await exeIcon.exists()) {
        return exeIcon.absolute.path;
      }

      // Extract from Flutter asset bundle to app support dir as guaranteed fallback
      final supportDir = await getApplicationSupportDirectory();
      final targetFile = File('${supportDir.path}/app_tray_icon.ico');
      try {
        final byteData = await rootBundle.load('assets/app_icon.ico');
        await targetFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      } catch (_) {}
      return targetFile.path;
    } catch (_) {
      return 'windows/runner/resources/app_icon.ico';
    }
  }

  Future<void> updateContextMenu() async {
    try {
      final isStartup = await launchAtStartup.isEnabled();
      final menu = Menu(
        items: [
          MenuItem(
            key: 'quick_record',
            label: '⚡ Quick Record (Ctrl+Shift+B)',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'show_app',
            label: 'Open ThoughtHolder',
          ),
          MenuItem(
            key: 'hide_app',
            label: 'Minimize to Tray',
          ),
          MenuItem.separator(),
          MenuItem.checkbox(
            key: 'toggle_startup',
            label: 'Launch at Startup',
            checked: isStartup,
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit_app',
            label: 'Exit ThoughtHolder',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('[DesktopManager] updateContextMenu warning: $e');
    }
  }

  Future<void> _initGlobalHotKey() async {
    try {
      await hotKeyManager.unregisterAll();
      final hotKey = HotKey(
        key: PhysicalKeyboardKey.keyB,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );

      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (hotKey) {
          debugPrint('[DesktopManager] Global hotkey Ctrl+Shift+B triggered');
          popupAndRecord();
        },
      );
    } catch (e) {
      debugPrint('[DesktopManager] Hotkey registration error: $e');
    }
  }

  /// Pops up the window, brings it to front (always-on-top widget mode),
  /// and automatically triggers voice capture.
  Future<void> popupAndRecord() async {
    if (!isDesktop) return;
    try {
      final isVisible = await windowManager.isVisible();
      if (!isVisible) {
        await windowManager.show();
      }
      final isMin = await windowManager.isMinimized();
      if (isMin) {
        await windowManager.restore();
      }

      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);

      // Trigger recording in CaptureScreen
      recordRequested.value = true;
    } catch (e) {
      debugPrint('[DesktopManager] popupAndRecord error: $e');
    }
  }

  Future<void> showAndFocus() async {
    if (!isDesktop) return;
    try {
      final isVisible = await windowManager.isVisible();
      if (!isVisible) {
        await windowManager.show();
      }
      final isMin = await windowManager.isMinimized();
      if (isMin) {
        await windowManager.restore();
      }
      await windowManager.focus();
    } catch (e) {
      debugPrint('[DesktopManager] showAndFocus error: $e');
    }
  }

  Future<void> hideToTray() async {
    if (!isDesktop) return;
    try {
      await windowManager.hide();
    } catch (e) {
      debugPrint('[DesktopManager] hideToTray error: $e');
    }
  }

  Future<void> toggleLaunchAtStartup(bool enable) async {
    if (!isDesktop) return;
    try {
      if (enable) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      await _settingsService?.setLaunchAtStartup(enable);
      await updateContextMenu();
    } catch (e) {
      debugPrint('[DesktopManager] toggleLaunchAtStartup error: $e');
    }
  }

  Future<void> quitApp() async {
    try {
      await hotKeyManager.unregisterAll();
      await trayManager.destroy();
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  // --- WindowListener Callbacks ---

  @override
  void onWindowClose() async {
    final closeToTray = _settingsService?.closeToTray ?? true;
    if (closeToTray) {
      await windowManager.hide();
    } else {
      await quitApp();
    }
  }

  @override
  void onWindowFocus() {
    // Normal focus resumed
  }

  // --- TrayListener Callbacks ---

  @override
  void onTrayIconMouseDown() async {
    await showAndFocus();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'quick_record':
        await popupAndRecord();
        break;
      case 'show_app':
        await showAndFocus();
        break;
      case 'hide_app':
        await hideToTray();
        break;
      case 'toggle_startup':
        final isCurrentlyEnabled = await launchAtStartup.isEnabled();
        await toggleLaunchAtStartup(!isCurrentlyEnabled);
        break;
      case 'exit_app':
        await quitApp();
        break;
    }
  }
}
