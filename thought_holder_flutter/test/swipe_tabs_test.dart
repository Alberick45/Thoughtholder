import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thought_holder_flutter/widgets/swipe_tabs.dart';

void main() {
  testWidgets('SwipeTabs: dragging left on Sorted lands on Unsorted and updates tab',
      (WidgetTester tester) async {
    int activeIndex = 0;
    double progress = 0.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  Row(
                    children: [
                      Text(activeIndex == 0 ? 'Pill: Sorted' : 'Pill: Unsorted'),
                    ],
                  ),
                  Expanded(
                    child: SwipeTabs(
                      currentIndex: activeIndex,
                      tabLabels: const ['Sorted', 'Unsorted'],
                      thresholdFraction: 0.30,
                      onDragProgress: (p) => progress = p,
                      onTabChanged: (idx) {
                        setState(() => activeIndex = idx);
                      },
                      children: const [
                        Center(child: Text('Content Sorted')),
                        Center(child: Text('Content Unsorted')),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Content Sorted'), findsOneWidget);
    expect(find.text('Pill: Sorted'), findsOneWidget);

    // Drag left past 30% of screen width (screen is 800px wide, drag -300px)
    await tester.drag(find.text('Content Sorted'), const Offset(-320, 0));
    await tester.pumpAndSettle();

    expect(activeIndex, 1);
    expect(progress, 1.0);
    expect(find.text('Pill: Unsorted'), findsOneWidget);
    expect(find.text('Content Unsorted'), findsOneWidget);
  });

  testWidgets('SwipeTabs: drag starting in SwipeExclusion (bucket slider) does NOT change tab',
      (WidgetTester tester) async {
    int activeIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SwipeTabs(
                currentIndex: activeIndex,
                thresholdFraction: 0.30,
                onTabChanged: (idx) {
                  setState(() => activeIndex = idx);
                },
                children: [
                  Column(
                    children: [
                      const Text('Header Sorted'),
                      SwipeExclusion(
                        child: Container(
                          key: const ValueKey('bucket_slider'),
                          height: 120,
                          width: double.infinity,
                          color: Colors.blue,
                          child: const Center(child: Text('Bucket Slider Area')),
                        ),
                      ),
                    ],
                  ),
                  const Center(child: Text('Content Unsorted')),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(activeIndex, 0);

    // Drag left starting inside the SwipeExclusion
    await tester.drag(find.byKey(const ValueKey('bucket_slider')), const Offset(-350, 0));
    await tester.pumpAndSettle();

    // Tab must NOT have changed!
    expect(activeIndex, 0);
    expect(find.text('Header Sorted'), findsOneWidget);
  });

  testWidgets('SwipeTabs: swiping is disabled when enabled = false (e.g. sheet open)',
      (WidgetTester tester) async {
    int activeIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeTabs(
            currentIndex: activeIndex,
            enabled: false, // Sheet/dialog open or setting disabled
            thresholdFraction: 0.30,
            onTabChanged: (idx) => activeIndex = idx,
            children: const [
              Center(child: Text('Tab 1 Content')),
              Center(child: Text('Tab 2 Content')),
            ],
          ),
        ),
      ),
    );

    await tester.drag(find.text('Tab 1 Content'), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(activeIndex, 0);
    expect(find.text('Tab 1 Content'), findsOneWidget);
  });

  testWidgets('SwipeTabs: at the last tab a left drag springs back',
      (WidgetTester tester) async {
    int activeIndex = 1; // Last tab

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeTabs(
            currentIndex: activeIndex,
            thresholdFraction: 0.30,
            onTabChanged: (idx) => activeIndex = idx,
            children: const [
              Center(child: Text('Tab 1 Content')),
              Center(child: Text('Tab 2 Content')),
            ],
          ),
        ),
      ),
    );

    // At Tab 2, drag left (attempting to go beyond last tab)
    await tester.drag(find.text('Tab 2 Content'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(activeIndex, 1);
    expect(find.text('Tab 2 Content'), findsOneWidget);
  });

  testWidgets('SwipeTabs: vertical drag scrolls and does not change the tab',
      (WidgetTester tester) async {
    int activeIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeTabs(
            currentIndex: activeIndex,
            thresholdFraction: 0.30,
            onTabChanged: (idx) => activeIndex = idx,
            children: [
              ListView(
                children: const [
                  SizedBox(height: 100, child: Text('List Item 1')),
                  SizedBox(height: 100, child: Text('List Item 2')),
                  SizedBox(height: 100, child: Text('List Item 3')),
                  SizedBox(height: 600, child: Text('List Item 4')),
                ],
              ),
              const Center(child: Text('Tab 2 Content')),
            ],
          ),
        ),
      ),
    );

    // Drag vertically
    await tester.drag(find.text('List Item 1'), const Offset(0, -250));
    await tester.pumpAndSettle();

    expect(activeIndex, 0);
    expect(find.text('List Item 4'), findsOneWidget);
  });

  testWidgets('SwipeTabs: reduced motion settles without animation',
      (WidgetTester tester) async {
    int activeIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    ElevatedButton(
                      onPressed: () => setState(() => activeIndex = 1),
                      child: const Text('Switch Tab'),
                    ),
                    Expanded(
                      child: SwipeTabs(
                        currentIndex: activeIndex,
                        thresholdFraction: 0.30,
                        onTabChanged: (idx) => setState(() => activeIndex = idx),
                        children: const [
                          Center(child: Text('Tab 1')),
                          Center(child: Text('Tab 2')),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    // Tap switch tab
    await tester.tap(find.text('Switch Tab'));
    // Pump single frame
    await tester.pump();

    // With reduced motion, it settles immediately without multi-frame animation
    expect(find.text('Tab 2'), findsOneWidget);
  });

  testWidgets('SwipeTabs: tapping a pill changes tab',
      (WidgetTester tester) async {
    int activeIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () => setState(() => activeIndex = 0),
                        child: const Text('Pill Sorted'),
                      ),
                      ElevatedButton(
                        onPressed: () => setState(() => activeIndex = 1),
                        child: const Text('Pill Unsorted'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: SwipeTabs(
                      currentIndex: activeIndex,
                      onTabChanged: (idx) => setState(() => activeIndex = idx),
                      children: const [
                        Center(child: Text('Page Sorted')),
                        Center(child: Text('Page Unsorted')),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Page Sorted'), findsOneWidget);

    await tester.tap(find.text('Pill Unsorted'));
    await tester.pumpAndSettle();

    expect(activeIndex, 1);
    expect(find.text('Page Unsorted'), findsOneWidget);

    await tester.tap(find.text('Pill Sorted'));
    await tester.pumpAndSettle();

    expect(activeIndex, 0);
    expect(find.text('Page Sorted'), findsOneWidget);
  });

  testWidgets('SwipeTabs: Ctrl+PageDown and Ctrl+PageUp switch tabs',
      (WidgetTester tester) async {
    int activeIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () {
                    if (activeIndex < 1) setState(() => activeIndex = 1);
                  },
                  const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () {
                    if (activeIndex > 0) setState(() => activeIndex = 0);
                  },
                },
                child: Focus(
                  autofocus: true,
                  child: SwipeTabs(
                    currentIndex: activeIndex,
                    onTabChanged: (idx) => setState(() => activeIndex = idx),
                    children: const [
                      Center(child: Text('Content Tab 1')),
                      Center(child: Text('Content Tab 2')),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(activeIndex, 0);

    // Press Ctrl+PageDown
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(activeIndex, 1);
    expect(find.text('Content Tab 2'), findsOneWidget);

    // Press Ctrl+PageUp
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(activeIndex, 0);
    expect(find.text('Content Tab 1'), findsOneWidget);
  });

  testWidgets('SwipeTabs: each tab retains its state across tab switches',
      (WidgetTester tester) async {
    int activeIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => activeIndex = activeIndex == 0 ? 1 : 0),
                    child: const Text('Toggle Tab'),
                  ),
                  Expanded(
                    child: SwipeTabs(
                      currentIndex: activeIndex,
                      onTabChanged: (idx) => setState(() => activeIndex = idx),
                      children: const [
                        _StatefulTestChild(title: 'Tab 1 Child'),
                        _StatefulTestChild(title: 'Tab 2 Child'),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Tab 1 Child Counter: 0'), findsOneWidget);

    // Increment counter in Tab 1
    await tester.tap(find.text('Increment Tab 1 Child'));
    await tester.pump();
    expect(find.text('Tab 1 Child Counter: 1'), findsOneWidget);

    // Switch to Tab 2
    await tester.tap(find.text('Toggle Tab'));
    await tester.pumpAndSettle();
    expect(find.text('Tab 2 Child Counter: 0'), findsOneWidget);

    // Switch back to Tab 1
    await tester.tap(find.text('Toggle Tab'));
    await tester.pumpAndSettle();

    // Tab 1 state MUST still be counter: 1!
    expect(find.text('Tab 1 Child Counter: 1'), findsOneWidget);
  });
}

class _StatefulTestChild extends StatefulWidget {
  final String title;
  const _StatefulTestChild({required this.title});

  @override
  State<_StatefulTestChild> createState() => _StatefulTestChildState();
}

class _StatefulTestChildState extends State<_StatefulTestChild> {
  int counter = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('${widget.title} Counter: $counter'),
        ElevatedButton(
          onPressed: () => setState(() => counter++),
          child: Text('Increment ${widget.title}'),
        ),
      ],
    );
  }
}
