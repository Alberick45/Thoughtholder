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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThoughtProvider()),
        ChangeNotifierProvider(create: (_) => GamificationProvider()),
        ChangeNotifierProvider(create: (_) => NavigationNotifier()),
        ChangeNotifierProvider(create: (_) => BackgroundRecordingService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<SoundService>.value(value: SoundService.instance),
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
    });

    if (!kIsWeb && Platform.isAndroid) {
      // Cold start: app was launched by tapping the widget
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
      // Warm start: app already open/backgrounded
      HomeWidget.widgetClicked.listen(_handleWidgetUri);
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationNotifier>();
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final currentIndex = nav.mainTabIndex;
    final bool isBucketOpen = (currentIndex == 1 && nav.streamSubTab == 'sorted' && nav.selectedBucket != null);

    final pages = [
      const CaptureScreen(),
      const StreamScreen(),
    ];

    return PopScope(
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
        if (!kIsWeb && Platform.isAndroid) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: colors.bg,
        appBar: AppBar(
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
        body: pages[currentIndex],
        bottomNavigationBar: isBucketOpen
            ? null
            : Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.line, width: 2)),
                ),
                child: BottomNavigationBar(
            currentIndex: currentIndex,
            onTap: (index) => context.read<NavigationNotifier>().setMainTab(index),
            backgroundColor: colors.card,
            selectedItemColor: colors.gold,
            unselectedItemColor: colors.mute,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.mic_outlined, size: 26),
                activeIcon: Icon(Icons.mic, size: 26),
                label: 'Capture',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.auto_awesome_outlined, size: 26),
                activeIcon: Icon(Icons.auto_awesome, size: 26),
                label: 'Stream',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
