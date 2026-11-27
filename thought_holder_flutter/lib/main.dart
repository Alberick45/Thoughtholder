import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:google_fonts/google_fonts.dart';
import 'thought_provider.dart';
import 'stream_screen.dart';
import 'capture_screen.dart';
import 'settings_modal.dart';
import 'google_drive_service.dart';
import 'sender_service.dart';
import 'receiver_service.dart';
import 'settings_service.dart';
import 'history_service.dart';
import 'gamification_provider.dart';
import 'services/gamification_service.dart';
import 'navigation_service.dart';
import 'app_theme.dart';
import 'package:home_widget/home_widget.dart';
import 'desktop_manager.dart';

import 'background_recording_service.dart';
import 'notification_service.dart';
import 'sound_service.dart';
import 'starter_buckets_screen.dart';
import 'utils/global_error_handler.dart';
import 'services/self_check_service.dart';
import 'settings/diagnostics_screen.dart';
import 'widgets/swipe_tabs.dart';
import 'services/app_update_service.dart';
import 'services/backup_service.dart';
import 'services/database_migration_service.dart';
import 'widgets/migration_failure_screen.dart';
import 'widgets/update_sheets.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GlobalErrorHandler.init();

  // Initialize SQLite FFI for Desktop platforms (Windows / Linux)
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize Hive in the app-specific support directory to avoid
  // lock conflicts between debug and installed (MSIX) instances.
  final appSupportDir = await getApplicationSupportDirectory();
  await Hive.initFlutter(appSupportDir.path);

  // Initialize BLE & core settings services
  final settingsService = SettingsService();
  await settingsService.init();

  final historyService = HistoryService();
  await historyService.init();

  final senderService = SenderService();
  final receiverService = ReceiverService(settingsService, historyService);

  // Initialize Desktop Manager (System tray, global hotkey Ctrl+Shift+B, window close-to-tray, startup)
  if (DesktopManager.isDesktop) {
    await DesktopManager.instance.init(settingsService);
  }

  // Initialize SoundService (preloads feedback tones for low latency)
  await SoundService.instance.preload();

  // Initialize Gamification & Daily Goals
  await GamificationService.instance.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThoughtProvider()),
        ChangeNotifierProvider(create: (_) => GamificationProvider()),
        ChangeNotifierProvider<GamificationService>.value(value: GamificationService.instance),
        ChangeNotifierProvider(create: (_) => NavigationNotifier()),
        ChangeNotifierProvider(create: (_) => BackgroundRecordingService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<SoundService>.value(value: SoundService.instance),
        ChangeNotifierProvider<AppUpdateService>.value(value: AppUpdateService.instance),
        Provider<GoogleDriveService>(create: (_) => GoogleDriveService()),
        Provider<HistoryService>.value(value: historyService),
        Provider<SenderService>.value(value: senderService),
        Provider<ReceiverService>.value(value: receiverService),
      ],
      child: const ThoughtHolderApp(),
    ),
  );
}

class ThoughtHolderApp extends StatelessWidget {
  const ThoughtHolderApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (DatabaseMigrationService.instance.migrationError != null) {
      return MigrationFailureScreen(
        backupPath: DatabaseMigrationService.instance.lastSafeBackupPath ?? '',
        errorMessage: DatabaseMigrationService.instance.migrationError,
      );
    }

    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    return MaterialApp(
      title: 'ThoughtHolder',
      scaffoldMessengerKey: GlobalErrorHandler.messengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: colors.brightness,
        primaryColor: colors.gold,
        scaffoldBackgroundColor: colors.bg,
        cardColor: colors.card,
        dividerColor: colors.line,
        colorScheme: ColorScheme(
          brightness: colors.brightness,
          primary: colors.gold,
          onPrimary: Colors.black,
          secondary: colors.gold,
          onSecondary: Colors.black,
          error: colors.bad,
          onError: Colors.white,
          surface: colors.card,
          onSurface: colors.text,
        ),
        textTheme: GoogleFonts.atkinsonHyperlegibleTextTheme(
          ThemeData(brightness: colors.brightness).textTheme,
        ).apply(
          bodyColor: colors.text,
          displayColor: colors.text,
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Check for any recovered unfinished recordings
      context.read<BackgroundRecordingService>().checkUnfinishedRecording();

      // Connect notification service dependencies and settings to ThoughtProvider
      final nav = context.read<NavigationNotifier>();
      final provider = context.read<ThoughtProvider>();
      final settings = context.read<SettingsService>();
      provider.updateSettings(settings);

      context.read<NotificationService>().updateDependencies(
            navigation: nav,
            provider: provider,
            settings: settings,
          );
      settings.recordAppActiveTime();

      // UPDATE 6 - Section B & D: Starter buckets for new users & migration
      if (!settings.hasChosenStarterBuckets) {
        if (provider.buckets.isNotEmpty || provider.thoughts.isNotEmpty) {
          // Existing user with data: migrate without showing the screen
          await settings.setHasChosenStarterBuckets(true);
        } else {
          // Fresh user: Show "Pick your starter buckets" screen once
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StarterBucketsScreen()),
            );
          }
        }
      }

      await _maybeOfferRawDefaultRecovery(provider, settings);

      // Startup self-check: fast, non-blocking, completely silent when everything is fine
      Future.delayed(const Duration(milliseconds: 300), () async {
        if (!mounted) return;
        try {
          final report = await SelfCheckService.instance.runSelfCheck();
          if (report.hasIssues && mounted) {
            final critical = report.overallStatus == CheckStatus.red;
            final issue = report.items.firstWhere(
              (i) => i.status == CheckStatus.red,
              orElse: () => report.items.firstWhere(
                (i) => i.status == CheckStatus.amber,
                orElse: () => report.items.first,
              ),
            );

            GlobalErrorHandler.messengerKey.currentState?.showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 8),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 94),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      issue.summary,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    const Text('Your ideas are completely safe.'),
                  ],
                ),
                action: SnackBarAction(
                  label: critical ? 'Restore' : 'Fix it',
                  textColor: const Color(0xFFFFD54F),
                  onPressed: () async {
                    if (critical) {
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
                      );
                    } else {
                      final res = await SelfCheckService.instance.performSafeSelfRepair();
                      GlobalErrorHandler.messengerKey.currentState?.showSnackBar(
                        SnackBar(
                          content: Text(res.message),
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.only(bottom: 96, left: 16, right: 16),
                        ),
                      );
                    }
                  },
                ),
              ),
            );
          }
        } catch (_) {}
      });

      // In-app update check: once per 24 hours on launch
      Future.delayed(const Duration(seconds: 2), () async {
        if (!mounted) return;
        final recService = context.read<BackgroundRecordingService>();
        if (AppUpdateService.instance.isVoiceCaptureActive(recService)) return;

        try {
          final manifest = await AppUpdateService.instance.checkForUpdates(
            settings: settings,
            manual: false,
          );
          if (manifest != null && mounted) {
            final isAvail = await AppUpdateService.instance.isUpdateAvailable(
              manifest: manifest,
              settings: settings,
            );
            if (isAvail && mounted) {
              final isReq = await AppUpdateService.instance.isUpdateRequired(manifest);
              final installed = await AppUpdateService.instance.getInstalledVersion();
              if (mounted) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  isDismissible: !isReq,
                  enableDrag: !isReq,
                  backgroundColor: Colors.transparent,
                  builder: (sheetCtx) => UpdateAvailableSheet(
                    manifest: manifest,
                    installedVersion: installed.versionName,
                    isRequired: isReq,
                    onStartUpdate: () {
                      Navigator.of(sheetCtx).pop();
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        isDismissible: false,
                        enableDrag: false,
                        backgroundColor: Colors.transparent,
                        builder: (modalCtx) => UpdatingModal(
                          manifest: manifest,
                          onRetry: () {
                            AppUpdateService.instance.startUpdate(
                              manifest: manifest,
                              settings: settings,
                              recordingService: recService,
                            );
                          },
                          onCancel: () {
                            AppUpdateService.instance.cancelUpdate();
                            Navigator.of(modalCtx).pop();
                          },
                        ),
                      );

                      AppUpdateService.instance.startUpdate(
                        manifest: manifest,
                        settings: settings,
                        recordingService: recService,
                      );
                    },
                  ),
                );
              }
            }
          }
        } catch (_) {}
      });
    });

    if (!kIsWeb && Platform.isAndroid) {
      // Cold start: app was launched by tapping the widget
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
      // Warm start: app already open/backgrounded
      HomeWidget.widgetClicked.listen(_handleWidgetUri);
    }
  }

  double _liveMainPage = 0.0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<SettingsService>().recordAppActiveTime();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleWidgetUri(Uri? uri) {
    // UPDATE 5 - Section A: Every entry point opens Capture in idle state, never records.
    context.read<NavigationNotifier>().goToCapture();
  }

  Future<void> _maybeOfferRawDefaultRecovery(
    ThoughtProvider provider,
    SettingsService settings,
  ) async {
    if (!mounted || settings.hasOfferedRawDefaultRecovery) return;
    final cutoff = DateTime.utc(2026, 11, 23, 1, 24, 31).millisecondsSinceEpoch;
    final candidates =
        await provider.fetchRawDefaultRecoveryCandidates(cutoff);
    await settings.setHasOfferedRawDefaultRecovery(true);
    if (!mounted || candidates.isEmpty) return;

    final count = candidates.length;
    final selectedIds = <String>{...candidates.map((e) => e['id'].toString())};
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Move recent Raw items back to Unsorted?'),
          content: SizedBox(
            width: 560,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count recent thought${count == 1 ? '' : 's'} landed in Raw because Raw was the default capture bucket. '
                  'Untick any you filed in Raw on purpose. Done items are excluded.',
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (_, i) {
                      final t = candidates[i];
                      final id = t['id'].toString();
                      final raw = (t['content'] ?? t['title'] ?? '').toString().trim();
                      final text = raw.isEmpty ? '(untitled)' : raw;
                      final checked = selectedIds.contains(id);
                      return CheckboxListTile(
                        value: checked,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          text.length > 110 ? '${text.substring(0, 110)}...' : text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selectedIds.add(id);
                            } else {
                              selectedIds.remove(id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'A backup will be created before moving. Raw remains a normal bucket.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep in Raw'),
            ),
            FilledButton(
              onPressed: selectedIds.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: Text('Move ${selectedIds.length} to Unsorted'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await BackupService.instance.createBackup(
        customFileName:
            'pre_raw_recovery_${DateTime.now().millisecondsSinceEpoch}.db',
      );
      final moved = await provider.moveRawThoughtsToUnsorted(selectedIds.toList());
      if (!mounted) return;
      GlobalErrorHandler.messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Moved $moved item${moved == 1 ? '' : 's'} to Unsorted. Backup created.')),
      );
    } catch (e) {
      if (!mounted) return;
      GlobalErrorHandler.messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Could not move Raw items: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationNotifier>();
    final settings = context.watch<SettingsService>();
    final bgRecording = context.watch<BackgroundRecordingService>();
    final colors = AppColors.of(settings.theme);
    final currentIndex = nav.mainTabIndex;
    final bool isBucketOpen = (currentIndex == 1 && nav.streamSubTab == 'sorted' && nav.selectedBucket != null);
    final bool isBoardFullscreen = (currentIndex == 1 && nav.isBoardExpanded && !nav.isTrashOpen && nav.selectedBucket == null);

    final liveIndex = _liveMainPage.round().clamp(0, 1);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () {
          if (nav.mainTabIndex < 1) {
            nav.setMainTab(1);
          }
        },
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () {
          if (nav.mainTabIndex > 0) {
            nav.setMainTab(0);
          }
        },
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (nav.selectedBucket != null) {
            nav.selectBucket(null);
            return;
          }
          if (nav.isTrashOpen) {
            nav.closeTrash();
            return;
          }
          if (nav.isBoardExpanded) {
            nav.setBoardExpanded(false);
            return;
          }
          if (!kIsWeb && Platform.isAndroid) {
            SystemNavigator.pop();
          }
        },
        child: Scaffold(
          backgroundColor: colors.bg,
          appBar: isBoardFullscreen
              ? null
              : AppBar(
                  automaticallyImplyLeading: false,
                  title: Text(
                    'BRAIN DUMP',
                    style: TextStyle(
                      color: colors.gold,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      fontSize: 17,
                    ),
                  ),
                  centerTitle: true,
                  backgroundColor: colors.bg,
                  elevation: 0,
                  actions: [
                    IconButton(
                      icon: Icon(Icons.settings_outlined, color: colors.mute),
                      tooltip: 'Settings: connect Groq',
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const SettingsModal(),
                        );
                      },
                    ),
                  ],
                ),
          body: SwipeTabs(
            currentIndex: currentIndex,
            tabLabels: const ['Speak', 'Board'],
            enabled: settings.swipeCaptureStream &&
                !isBucketOpen &&
                !nav.isTrashOpen &&
                !bgRecording.isRecording &&
                MediaQuery.viewInsetsOf(context).bottom == 0,
            thresholdFraction: settings.swipeThresholdFraction,
            isRecording: bgRecording.isRecording,
            onDragProgress: (page) {
              if ((page - _liveMainPage).abs() > 0.05) {
                setState(() => _liveMainPage = page);
              }
            },
            onTabChanged: (index) {
              setState(() => _liveMainPage = index.toDouble());
              nav.setMainTab(index);
            },
            children: const [
              CaptureScreen(),
              StreamScreen(),
            ],
          ),
          bottomNavigationBar: isBucketOpen
              ? null
              : Container(
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: colors.line, width: 2)),
                  ),
                  child: BottomNavigationBar(
              currentIndex: liveIndex,
              onTap: (index) {
                if (index == 1 && nav.mainTabIndex == 1) {
                  nav.toggleBoardExpanded();
                } else {
                  setState(() => _liveMainPage = index.toDouble());
                  context.read<NavigationNotifier>().setMainTab(index);
                }
              },
              backgroundColor: colors.card,
              selectedItemColor: colors.gold,
              unselectedItemColor: colors.mute,
              selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              items: [
                BottomNavigationBarItem(
                  icon: Semantics(
                    label: 'Speak, tab 1 of 2${liveIndex == 0 ? ', selected' : ''}',
                    child: const Icon(Icons.mic_outlined, size: 26),
                  ),
                  activeIcon: Semantics(
                    label: 'Speak, tab 1 of 2, selected',
                    child: const Icon(Icons.mic, size: 26),
                  ),
                  label: 'Speak',
                ),
                BottomNavigationBarItem(
                  icon: Semantics(
                    label: 'Board, tab 2 of 2${liveIndex == 1 ? ', selected' : ''}',
                    child: const Icon(Icons.push_pin_outlined, size: 26),
                  ),
                  activeIcon: Semantics(
                    label: 'Board, tab 2 of 2, selected',
                    child: const Icon(Icons.push_pin, size: 26),
                  ),
                  label: 'Board',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}