import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/settings/settings_registry.dart';
import 'package:thought_holder_flutter/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('STEP 4: Making Buckets Elsewhere', () {
    final entries = SettingsRegistry.getEntries();

    test('1. "Make a new bucket" is registered in Settings under Ideas and buckets', () {
      final matches = entries.where((e) => e.id == 'make_new_bucket').toList();
      expect(matches, isNotEmpty);
      final entry = matches.first;
      expect(entry.title, equals('Make a new bucket'));
      expect(entry.group, equals('Ideas and buckets'));
      expect(entry.description, contains('name and icon'));
    });

    test('2. Settings search finds "Make a new bucket" via keywords', () {
      expect(entries.any((e) => e.matches('bucket') && e.id == 'make_new_bucket'), isTrue);
      expect(entries.any((e) => e.matches('make') && e.id == 'make_new_bucket'), isTrue);
      expect(entries.any((e) => e.matches('new bucket') && e.id == 'make_new_bucket'), isTrue);
      expect(entries.any((e) => e.matches('custom') && e.id == 'make_new_bucket'), isTrue);
    });

    test('3. Predefined bucket icons has exactly 12 icons with valid IconData', () {
      expect(kBucketIcons.length, equals(12));
      expect(kBucketIcons.containsKey('folder'), isTrue);
      expect(kBucketIcons.containsKey('book'), isTrue);
      expect(kBucketIcons.containsKey('briefcase'), isTrue);
      expect(kBucketIcons.containsKey('bulb'), isTrue);
      expect(kBucketIcons.containsKey('heart'), isTrue);
      expect(kBucketIcons.containsKey('star'), isTrue);
      expect(kBucketIcons.containsKey('home'), isTrue);
      expect(kBucketIcons.containsKey('code'), isTrue);
      expect(kBucketIcons.containsKey('music'), isTrue);
      expect(kBucketIcons.containsKey('chart'), isTrue);
      expect(kBucketIcons.containsKey('cart'), isTrue);
      expect(kBucketIcons.containsKey('person'), isTrue);

      for (final icon in kBucketIcons.values) {
        expect(icon, isNotNull);
      }
    });
  });
}
