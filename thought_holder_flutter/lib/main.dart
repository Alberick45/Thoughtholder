import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
import 'package:home_widget/home_widget.dart';
import 'record_trigger.dart';
import 'desktop_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThoughtProvider()),
        ChangeNotifierProvider(create: (_) => GamificationProvider()),
        ChangeNotifierProvider(create: (_) => NavigationNotifier()),
        Provider<GoogleDriveService>(create: (_) => GoogleDriveService()),
        Provider<SettingsService>.value(value: settingsService),
        Provider<HistoryService>.value(value: historyService),
        Provider<SenderService>.value(value: senderService),
        Provider<ReceiverService>.value(value: receiverService),
      ],
      child: const ThoughtHolderApp(),
    ),
  );
}

class ThoughtHolderApp extends StatelessWidget {
  const ThoughtHolderApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThoughtHolder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFFFBF00),
        scaffoldBackgroundColor: const Color(0xFF0E0E10),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFBF00),
          secondary: Color(0xFF4A90E2),
          surface: Color(0xFF1F1F21),
        ),
        fontFamily: 'monospace',
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({Key? key}) : super(key: key);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isAndroid) {
      // Cold start: app was launched by tapping the widget
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleWidgetUri);
      // Warm start: app already open/backgrounded
      HomeWidget.widgetClicked.listen(_handleWidgetUri);
    }

    // Switch to Capture page whenever recording is triggered (e.g. from hotkey)
    recordRequested.addListener(_onRecordTriggered);
  }

  void _onRecordTriggered() {
    if (recordRequested.value && mounted) {
      context.read<NavigationNotifier>().goToCapture();
    }
  }

  @override
  void dispose() {
    recordRequested.removeListener(_onRecordTriggered);
    super.dispose();
  }

  void _handleWidgetUri(Uri? uri) {
    if (uri?.host == 'record') {
      context.read<NavigationNotifier>().goToCapture();
      recordRequested.value = true; // CaptureScreen picks this up
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationNotifier>();
    final currentIndex = nav.mainTabIndex;

    final pages = [
      const CaptureScreen(),
      const StreamScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BRAIN DUMP',
          style: TextStyle(
            color: Color(0xFFFFBF00),
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0E0E10),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF8E9192)),
            tooltip: 'Settings',
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
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1F1F21), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) => context.read<NavigationNotifier>().setMainTab(index),
          backgroundColor: const Color(0xFF131315),
          selectedItemColor: const Color(0xFFFFBF00),
          unselectedItemColor: const Color(0xFF8E9192),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.mic_outlined),
              activeIcon: Icon(Icons.mic),
              label: 'Capture',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome_outlined),
              activeIcon: Icon(Icons.auto_awesome),
              label: 'Stream',
            ),
          ],
        ),
      ),
    );
  }
}
