import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:thought_holder_flutter/settings_service.dart';
import 'package:thought_holder_flutter/secure_storage_service.dart';
import 'package:thought_holder_flutter/utils/app_logger.dart';
import 'package:thought_holder_flutter/services/self_check_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    tempDir = await Directory.systemTemp.createTemp('th_p5_test_');
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

  group('Phase 5 Item 1 - Groq Key Secure Storage & Sanitization Tests', () {
    test('SecureStorageService save, read, compare, and delete cycle', () async {
      const testSecret = 'gsk_secret_test_key_for_comparison_12345';
      await SecureStorageService.saveGroqApiKey(testSecret);

      final readBack = await SecureStorageService.getGroqApiKey();
      expect(readBack, equals(testSecret));

      await SecureStorageService.deleteGroqApiKey();
      final afterDelete = await SecureStorageService.getGroqApiKey();
      expect(afterDelete, isNull);

      final health = await SecureStorageService.testSecureStorageHealth();
      expect(health, isTrue);
    });

    test('AppLogger.sanitize redacts any gsk_ key from error and log messages', () {
      const realSampleKey = 'gsk_1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN';
      final dirtyMessage = 'Error connecting with authorization: Bearer $realSampleKey at endpoint';

      final sanitized = AppLogger.sanitize(dirtyMessage);

      expect(sanitized.contains(realSampleKey), isFalse);
      expect(sanitized.contains('gsk_'), isFalse);
      expect(sanitized, contains('[REDACTED_KEY]'));
      expect(sanitized, equals('Error connecting with authorization: Bearer [REDACTED_KEY] at endpoint'));
    });

    test('SettingsService maskedGroqApiKey shows only gsk_ prefix and last 4 characters', () async {
      final settings = SettingsService();
      await settings.init();

      const testKey = 'gsk_test1234567890abcdefghijklmnopqrstuvwxyz1234';
      await settings.setGroqApiKey(testKey);

      expect(settings.hasGroqKey, isTrue);
      final masked = settings.maskedGroqApiKey;

      expect(masked.startsWith('gsk_••••'), isTrue);
      expect(masked.endsWith('1234'), isTrue);
      expect(masked.contains('test1234567890'), isFalse);
    });

    test('removeGroqApiKey clears both in-memory cache and legacy plain settings box', () async {
      final settings = SettingsService();
      await settings.init();

      await settings.setGroqApiKey('gsk_to_be_removed_key_1234567890');
      expect(settings.hasGroqKey, isTrue);

      await settings.removeGroqApiKey();

      expect(settings.hasGroqKey, isFalse);
      expect(settings.groqApiKey, isEmpty);
      expect(settings.maskedGroqApiKey, isEmpty);
      expect(settings.hasLegacyGroqKeyInSettings, isFalse);
    });

    test('purgeLegacyGroqKeyFromSettings removes legacy Hive entry while preserving secure key', () async {
      final settings = SettingsService();
      await settings.init();

      // Simulate legacy key in Hive box
      await settings.setGroqApiKey('gsk_migrated_secure_key_1234567890');
      
      // Purge only legacy Hive copy
      await settings.purgeLegacyGroqKeyFromSettings();

      expect(settings.hasLegacyGroqKeyInSettings, isFalse);
      // Secure memory cache still holds the key
      expect(settings.hasGroqKey, isTrue);
      expect(settings.groqApiKey, isNotEmpty);
    });

    test('Diagnostic report contains zero secret keys, zero passwords, zero idea text', () {
      final report = SelfCheckReport(
        checkTime: DateTime.now(),
        durationMs: 12,
        overallStatus: CheckStatus.green,
        items: [
          const CheckItemResult(
            title: 'Secure storage',
            status: CheckStatus.green,
            summary: 'Hardware / OS credential vault operational',
            details: 'Write, read, and delete validation cycle succeeded without leaking secrets.',
          ),
          const CheckItemResult(
            title: 'Safety backups',
            status: CheckStatus.green,
            summary: 'Recent backup verified',
            details: '3 backups saved on disk.',
          ),
        ],
        totalIdeas: 700,
        liveIdeas: 650,
        doneIdeas: 40,
        trashedIdeas: 10,
        bucketCount: 5,
        backupCount: 3,
        lastBackupDate: DateTime.now(),
        databaseSizeBytes: 585728,
        databaseSchemaVersion: 3,
        appVersion: '1.0.0',
      );

      final text = report.toDiagnosticReport();

      expect(text.contains('gsk_'), isFalse);
      expect(text.contains('Bearer'), isFalse);
      expect(text.contains('key'), isFalse);
      expect(text.contains('Total ideas: 700'), isTrue);
      expect(text.contains('Hardware / OS credential vault operational'), isTrue);
    });
  });
}
