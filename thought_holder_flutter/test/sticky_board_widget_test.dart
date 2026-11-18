import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thought_holder_flutter/widgets/sticky_note_board.dart';
import 'package:thought_holder_flutter/thought_provider.dart';
import 'package:thought_holder_flutter/settings_service.dart';
import 'package:thought_holder_flutter/sound_service.dart';

void main() {
  late Directory tempDir;
  late SettingsService settingsService;
  late ThoughtProvider thoughtProvider;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const MethodChannel('plugins.flutter.io/path_provider')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      return Directory.systemTemp.path;
    });
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage')
        .setMockMethodCallHandler((MethodCall methodCall) async {
      return null;
    });

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('th_board_test_');
    Hive.init(tempDir.path);
    settingsService = SettingsService();
    await settingsService.init();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    thoughtProvider = ThoughtProvider();
  });

  testWidgets('StickyNoteBoard renders in quarter-screen and expanded modes without layout crash', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    bool sortedClicked = false;
    bool toggleClicked = false;

    // Test quarter-screen view
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThoughtProvider>.value(value: thoughtProvider),
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider<SoundService>.value(value: SoundService.instance),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StickyNoteBoard(
              isExpandedView: false,
              onOpenSorted: () => sortedClicked = true,
              onToggleExpand: () => toggleClicked = true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('PINNED BOARD'), findsOneWidget);
    expect(find.text('Expand Board'), findsOneWidget);

    // Test expanded view
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThoughtProvider>.value(value: thoughtProvider),
          ChangeNotifierProvider<SettingsService>.value(value: settingsService),
          ChangeNotifierProvider<SoundService>.value(value: SoundService.instance),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: StickyNoteBoard(
              isExpandedView: true,
              onOpenSorted: () => sortedClicked = true,
              onToggleExpand: () => toggleClicked = true,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('BRAIN DUMP • BOARD'), findsOneWidget);
    expect(find.text('Sort'), findsOneWidget);
    expect(find.textContaining('Sort: View all thoughts'), findsOneWidget);
    expect(find.text('0 / 8 pinned'), findsOneWidget);

    // Tap top Sort button
    await tester.tap(find.text('Sort'));
    await tester.pump();
    expect(sortedClicked, isTrue);

    sortedClicked = false;
    // Tap bottom Sort button
    await tester.tap(find.textContaining('Sort: View all thoughts'));
    await tester.pump();
    expect(sortedClicked, isTrue);
  });
}
