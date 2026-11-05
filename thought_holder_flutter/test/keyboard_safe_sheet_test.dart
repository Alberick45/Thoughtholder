import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/widgets/keyboard_safe_sheet.dart';
import 'package:thought_holder_flutter/utils/title_generator.dart';

void main() {
  group('KeyboardSafeSheet Tests', () {
    testWidgets('360x640 screen with viewInsets.bottom = 300: bottom edge is at or above keyboard top, search & create row visible, height equals opening height with 0 results, scrolls with 30 results', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Test with 0 results
      late BuildContext buildCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                buildCtx = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Open sheet with viewInsets.bottom = 300
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(() => tester.view.resetViewInsets());

      KeyboardSafeSheet.show(
        context: buildCtx,
        builder: (ctx) => KeyboardSafeSheet(
          openingHeight: 320.0,
          header: const SizedBox(key: Key('header'), height: 40, child: Text('Header')),
          pinnedHeader: Column(
            children: const [
              SizedBox(key: Key('search_field'), height: 56, child: Text('Search')),
              SizedBox(key: Key('create_row'), height: 56, child: Text('Create Row')),
            ],
          ),
          child: const SizedBox(key: Key('empty_results'), child: Text('No results')),
        ),
      );

      await tester.pumpAndSettle();

      final sheetFinder = find.byKey(KeyboardSafeSheet.containerKey);
      expect(sheetFinder, findsOneWidget);

      final sheetRect = tester.getRect(sheetFinder);
      // Bottom edge of the sheet must be at or above the keyboard top (640 - 300 = 340)
      expect(sheetRect.bottom, lessThanOrEqualTo(640 - 300));

      // Search field and create row are fully visible
      expect(find.byKey(const Key('search_field')), findsOneWidget);
      expect(find.byKey(const Key('create_row')), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('search_field'))).bottom, lessThanOrEqualTo(sheetRect.bottom));
      expect(tester.getRect(find.byKey(const Key('create_row'))).bottom, lessThanOrEqualTo(sheetRect.bottom));

      // With 0 results the height equals the opening height
      expect(sheetRect.height, equals(320.0));

      // Close sheet
      Navigator.pop(buildCtx);
      await tester.pumpAndSettle();

      // Now test with 30 results and scrolling
      final scrollController = ScrollController();
      KeyboardSafeSheet.show(
        context: buildCtx,
        builder: (ctx) => KeyboardSafeSheet(
          openingHeight: 320.0,
          header: const SizedBox(height: 40, child: Text('Header')),
          pinnedHeader: Column(
            children: const [
              SizedBox(key: Key('search_field_30'), height: 56, child: Text('Search')),
              SizedBox(key: Key('create_row_30'), height: 56, child: Text('Create Row')),
            ],
          ),
          child: ListView.builder(
            controller: scrollController,
            itemCount: 30,
            itemBuilder: (c, i) => SizedBox(
              height: 56,
              key: Key('item_$i'),
              child: Text('Item $i'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('item_0')), findsOneWidget);
      // Item 29 should not be visible initially before scrolling
      expect(find.byKey(const Key('item_29')), findsNothing);

      // Scroll the list
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();

      // After scrolling, the last item is rendered, verifying the list scrolls
      expect(find.byKey(const Key('item_29')), findsOneWidget);

      // Close sheet
      Navigator.pop(buildCtx);
      await tester.pumpAndSettle();
    });

    testWidgets('360x480 screen: trims to free space (480 - 300 - 0 - 12 = 168) and list scrolls; closing keyboard restores position', (tester) async {
      tester.view.physicalSize = const Size(360, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late BuildContext buildCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                buildCtx = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Keyboard starts closed (viewInsets.bottom = 0)
      tester.view.viewInsets = const FakeViewPadding(bottom: 0);
      addTearDown(() => tester.view.resetViewInsets());

      final scrollController = ScrollController();
      KeyboardSafeSheet.show(
        context: buildCtx,
        builder: (ctx) => KeyboardSafeSheet(
          openingHeight: 400.0,
          header: const SizedBox(height: 30, child: Text('Header')),
          pinnedHeader: const SizedBox(height: 40, child: Text('Search')),
          child: ListView.builder(
            controller: scrollController,
            itemCount: 20,
            itemBuilder: (c, i) => SizedBox(
              height: 56,
              key: Key('item_$i'),
              child: Text('Item $i'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      var sheetRect = tester.getRect(find.byKey(KeyboardSafeSheet.containerKey));
      expect(sheetRect.height, equals(400.0));
      expect(sheetRect.bottom, equals(480.0));

      // Now open keyboard (viewInsets.bottom = 300)
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      sheetRect = tester.getRect(find.byKey(KeyboardSafeSheet.containerKey));
      // Free space = 480 - 300 - 0 - 12 = 168.0
      expect(sheetRect.height, equals(168.0));
      expect(sheetRect.bottom, equals(480.0 - 300.0)); // sitting on keyboard

      // List scrolls in the trimmed space
      expect(find.byKey(const Key('item_0')), findsOneWidget);
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('item_19')), findsOneWidget);

      // Closing keyboard restores position
      tester.view.viewInsets = const FakeViewPadding(bottom: 0);
      await tester.pumpAndSettle();

      sheetRect = tester.getRect(find.byKey(KeyboardSafeSheet.containerKey));
      expect(sheetRect.height, equals(400.0));
      expect(sheetRect.bottom, equals(480.0));
    });

    test('Heading formatting rules', () {
      // 1. Title contains at least one letter or digit
      expect(
        KeyboardSafeSheet.formatIdeaHeading({'title': 'Church Project', 'content': 'details'}),
        equals('Church Project'),
      );
      // 2. Title with no letter or digit (apostrophe) -> cuts first 40 chars of text at word boundary
      expect(
        KeyboardSafeSheet.formatIdeaHeading({'title': "'", 'content': 'So first with age group scope is too large and we need to fix'}),
        equals('So first with age group scope is too'),
      );
      // 3. Short content (< 40 chars)
      expect(
        KeyboardSafeSheet.formatIdeaHeading({'title': "'", 'content': 'Short idea'}),
        equals('Short idea'),
      );
      // 4. Empty text -> "Empty idea", never ""
      expect(
        KeyboardSafeSheet.formatIdeaHeading({'title': "'", 'content': ''}),
        equals('Empty idea'),
      );
      expect(
        KeyboardSafeSheet.formatIdeaHeading({'title': '', 'content': '   '}),
        equals('Empty idea'),
      );
    });

    test('TitleGenerator apostrophe and alphanumeric rules', () {
      // 1. Text starting with "so" followed by quote or punctuation does not generate a lone quote
      expect(
        TitleGenerator.generate("so 'church project'"),
        equals('Church project'),
      );
      expect(
        TitleGenerator.generate("so, '...'"),
        equals('Quick note'),
      );

      // 2. Title must contain at least one letter or digit
      expect(
        TitleGenerator.generate("--- !!! ???"),
        equals('Quick note'),
      );

      // 3. getIdeaName never touches title_source = 'user'
      expect(
        TitleGenerator.getIdeaName({
          'title': '!',
          'title_source': 'user',
          'content': 'Some idea text',
        }),
        equals('!'),
      );

      // 4. getIdeaName regenerates if title_source is 'auto' and title has no letter/digit
      expect(
        TitleGenerator.getIdeaName({
          'title': "'",
          'title_source': 'auto',
          'content': 'So we should build a new garden shed',
        }),
        equals('We should build a new garden shed'),
      );
    });
  });
}
