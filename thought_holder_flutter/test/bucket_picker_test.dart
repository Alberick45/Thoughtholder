import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:thought_holder_flutter/thought_provider.dart';
import 'package:thought_holder_flutter/settings_service.dart';
import 'package:thought_holder_flutter/widgets/sticky_note_bucket_picker.dart';

class MockBucketThoughtProvider extends ThoughtProvider {
  final List<String> _mockBucketNames;

  MockBucketThoughtProvider(this._mockBucketNames);

  @override
  List<String> get bucketNames => _mockBucketNames;

  @override
  List<Map<String, dynamic>> get buckets =>
      _mockBucketNames.map((name) => {'name': name, 'id': name, 'icon': 'folder'}).toList();

  @override
  Future<String> addBucket(String name, {String icon = 'folder'}) async {
    if (!_mockBucketNames.contains(name)) {
      _mockBucketNames.add(name);
    }
    return name;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Widget buildTestWidget({
    String? initialBucket,
    required List<String> mockBuckets,
    required ValueChanged<String> onBucketChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<ThoughtProvider>(
          create: (_) => MockBucketThoughtProvider(mockBuckets),
          child: StickyNoteBucketPicker(
            initialBucket: initialBucket,
            onBucketChanged: onBucketChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('StickyNoteBucketPicker defaults to Raw and renders chips', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      buildTestWidget(
        mockBuckets: ['Work', 'Ideas'],
        onBucketChanged: (val) => chosen = val,
      ),
    );
    await tester.pumpAndSettle();

    // Default selection is Raw
    expect(chosen, equals('Raw'));
    expect(find.text('Raw'), findsWidgets);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Ideas'), findsOneWidget);
    expect(find.text('+ New bucket'), findsOneWidget);
  });

  testWidgets('StickyNoteBucketPicker allows selecting existing bucket without typing', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      buildTestWidget(
        mockBuckets: ['Work', 'Personal'],
        onBucketChanged: (val) => chosen = val,
      ),
    );
    await tester.pumpAndSettle();

    // Tap 'Work' chip
    await tester.tap(find.byKey(const Key('bucket_chip_Work')));
    await tester.pumpAndSettle();

    expect(chosen, equals('Work'));
  });

  testWidgets('+ New bucket opens text input and typing creates new bucket', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      buildTestWidget(
        mockBuckets: ['Work'],
        onBucketChanged: (val) => chosen = val,
      ),
    );
    await tester.pumpAndSettle();

    // Tap '+ New bucket'
    await tester.tap(find.byKey(const Key('bucket_chip_new')));
    await tester.pumpAndSettle();

    // Text field is visible
    expect(find.byKey(const Key('new_bucket_input_field')), findsOneWidget);

    // Type new bucket name
    await tester.enterText(find.byKey(const Key('new_bucket_input_field')), 'SideHustle');
    await tester.tap(find.byKey(const Key('new_bucket_confirm_btn')));
    await tester.pumpAndSettle();

    expect(chosen, equals('SideHustle'));
    expect(find.text('SideHustle'), findsWidgets);
  });

  testWidgets('Typing in filter field filters the bucket list', (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        mockBuckets: ['Work', 'Personal', 'Projects', 'Finance'],
        onBucketChanged: (_) {},
      ),
    );
    await tester.pumpAndSettle();

    // Filter field exists
    final searchFinder = find.byType(TextField);
    expect(searchFinder, findsOneWidget);

    // Enter 'pers' to filter
    await tester.enterText(searchFinder, 'pers');
    await tester.pumpAndSettle();

    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Work'), findsNothing);
    expect(find.text('Finance'), findsNothing);
  });
}
