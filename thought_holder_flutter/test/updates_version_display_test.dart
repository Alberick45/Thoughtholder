import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:thought_holder_flutter/settings/updates_group.dart';
import 'package:thought_holder_flutter/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    tempDir = await Directory.systemTemp.createTemp('th_updates_ui_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    try {
      await Hive.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets('Updates screen shows the injected installed version and build',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'ThoughtHolder',
      packageName: 'com.example.thoughtholder',
      version: '9.9.9',
      buildNumber: '99',
      buildSignature: '',
    );

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = SettingsService();
    await tester.runAsync(() async {
      await settings.init();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsService>.value(
        value: settings,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(0.5)),
            child: child!,
          ),
          home: const UpdatesGroupScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Version 9.9.9 (Build 99)'), findsOneWidget);
  });
}
