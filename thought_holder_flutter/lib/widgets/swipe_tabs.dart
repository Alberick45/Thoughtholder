import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../settings_service.dart';
import '../sound_service.dart';

/// Prevents parent [SwipeTabs] from initiating a tab swipe when drag
/// starts inside this widget (e.g. bucket slider, Capture text box, filter chips).
class SwipeExclusion extends StatelessWidget {
  final Widget child;

  static bool isExclusionActive = false;

  const SwipeExclusion({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        isExclusionActive = true;
      },
      onPointerUp: (_) {
        isExclusionActive = false;
      },
      onPointerCancel: (_) {
        isExclusionActive = false;
      },
      child: child,
    );
  }
}

/// Custom scroll physics that enforces:
/// 1. Drag distance threshold before committing to next page (e.g. 20%, 30%, 45%).
/// 2. Snappy settling time (<= 200 ms).
/// 3. Immediate snap (0 ms) when reduced motion is on.
/// 4. Disabling swipe when drag starts in edge area (24 dp) or excluded widget.
class ThresholdPageScrollPhysics extends PageScrollPhysics {
  final double thresholdFraction;
  final ValueGetter<bool> canDrag;
  final ValueGetter<int> dragStartPage;
  final bool disableAnimations;

  const ThresholdPageScrollPhysics({
    super.parent,
    this.thresholdFraction = 0.30,
    required this.canDrag,
    required this.dragStartPage,
    this.disableAnimations = false,
  });

  @override
  ThresholdPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ThresholdPageScrollPhysics(
      parent: buildParent(ancestor),
      thresholdFraction: thresholdFraction,
      canDrag: canDrag,
      dragStartPage: dragStartPage,
      disableAnimations: disableAnimations,
    );
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (!canDrag()) {
      return 0.0;
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    // If out of range at the edges, defer to parent for slight resistance & spring back.
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    if (position.viewportDimension <= 0) {
      return null;
    }

    final Tolerance tolerance = toleranceFor(position);
    final double page = position.pixels / position.viewportDimension;
    final int floorPage = page.floor();
    final double fraction = page - floorPage;
    final int start = dragStartPage();

    double targetPage;
    if (velocity < -tolerance.velocity) {
      // Flinging back (towards lower index)
      targetPage = floorPage.toDouble();
    } else if (velocity > tolerance.velocity) {
      // Flinging forward (towards higher index)
      targetPage = (floorPage + 1).toDouble();
    } else {
      // Released without fast fling: evaluate drag distance threshold
      if (start == floorPage) {
        // Dragged forward from floorPage
        if (fraction >= thresholdFraction) {
          targetPage = (floorPage + 1).toDouble();
        } else {
          targetPage = floorPage.toDouble();
        }
      } else {
        // Dragged backward from (floorPage + 1)
        if ((1.0 - fraction) >= thresholdFraction) {
          targetPage = floorPage.toDouble();
        } else {
          targetPage = (floorPage + 1).toDouble();
        }
      }
    }

    final double target = (targetPage * position.viewportDimension).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (target != position.pixels) {
      if (disableAnimations) {
        // Instant settle when reduced motion is on
        return ScrollSpringSimulation(
          const SpringDescription(mass: 0.1, stiffness: 10000.0, damping: 1.0),
          position.pixels,
          target,
          0.0,
          tolerance: tolerance,
        );
      }

      // Settles in <= 200 ms with short slide
      final SpringDescription fastSpring = SpringDescription.withDampingRatio(
        mass: 0.5,
        stiffness: 350.0,
        ratio: 1.1,
      );
      return ScrollSpringSimulation(fastSpring, position.pixels, target, velocity, tolerance: tolerance);
    }
    return null;
  }
}

/// Desktop scroll behavior: mouse drag is disabled to preserve text selection.
/// Touchscreens and trackpads retain swipe gestures.
class _SwipeTabsScrollBehavior extends MaterialScrollBehavior {
  const _SwipeTabsScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
      };
}

/// Shared tab swipe container used for:
/// 1. Sorted <-> Unsorted in StreamScreen
/// 2. Capture <-> Stream in MainScreen
class SwipeTabs extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTabChanged;
  final List<Widget> children;
  final List<String>? tabLabels;
  final bool enabled;
  final double thresholdFraction;
  final bool isRecording;
  final ValueChanged<double>? onDragProgress;
  final PageController? controller;

  const SwipeTabs({
    super.key,
    required this.currentIndex,
    required this.onTabChanged,
    required this.children,
    this.tabLabels,
    this.enabled = true,
    this.thresholdFraction = 0.30,
    this.isRecording = false,
    this.onDragProgress,
    this.controller,
  });

  @override
  State<SwipeTabs> createState() => _SwipeTabsState();
}

class _SwipeTabsState extends State<SwipeTabs> {
  late PageController _pageController;
  bool _internalController = false;
  int _dragStartPage = 0;
  bool _canDrag = true;
  int _lastSettledIndex = 0;

  @override
  void initState() {
    super.initState();
    _lastSettledIndex = widget.currentIndex;
    _dragStartPage = widget.currentIndex;
    if (widget.controller != null) {
      _pageController = widget.controller!;
    } else {
      _pageController = PageController(initialPage: widget.currentIndex);
      _internalController = true;
    }
    _pageController.addListener(_handleScrollProgress);
  }

  @override
  void didUpdateWidget(SwipeTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      _lastSettledIndex = widget.currentIndex;
      if (_pageController.hasClients &&
          (_pageController.page?.round() != widget.currentIndex)) {
        final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ??
            MediaQuery.of(context).disableAnimations;
        if (reducedMotion) {
          _pageController.jumpToPage(widget.currentIndex);
        } else {
          _pageController.animateToPage(
            widget.currentIndex,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  void _handleScrollProgress() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page ?? widget.currentIndex.toDouble();
    widget.onDragProgress?.call(page);
  }

  @override
  void dispose() {
    _pageController.removeListener(_handleScrollProgress);
    if (_internalController) {
      _pageController.dispose();
    }
    super.dispose();
  }

  void _onPageSettled(int index) {
    if (index == _lastSettledIndex) return;
    _lastSettledIndex = index;
    widget.onTabChanged(index);

    // Semantics announcement
    final total = widget.children.length;
    final label = (widget.tabLabels != null && index < widget.tabLabels!.length)
        ? widget.tabLabels![index]
        : 'Tab ${index + 1}';
    final message = '$label, tab ${index + 1} of $total, selected';
    try {
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        TextDirection.ltr,
      );
    } catch (_) {
      // ignore: deprecated_member_use
      SemanticsService.announce(message, TextDirection.ltr);
    }

    // Audio cue on settled swipe
    try {
      final settings = context.read<SettingsService>();
      if (settings.soundsEnabled &&
          settings.soundGroupSwipes &&
          !widget.isRecording) {
        SoundService.instance.play(SoundEvent.swipe, settings: settings);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ??
        MediaQuery.of(context).disableAnimations;

    final ScrollPhysics effectivePhysics;
    if (!widget.enabled) {
      effectivePhysics = const NeverScrollableScrollPhysics();
    } else {
      effectivePhysics = ThresholdPageScrollPhysics(
        thresholdFraction: widget.thresholdFraction,
        canDrag: () => _canDrag && !SwipeExclusion.isExclusionActive,
        dragStartPage: () => _dragStartPage,
        disableAnimations: reducedMotion,
        parent: const BouncingScrollPhysics(),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (SwipeExclusion.isExclusionActive) {
          _canDrag = false;
          return;
        }
        final screenWidth = MediaQuery.of(context).size.width;
        const double edgeMargin = 24.0;
        // Never start inside outermost 24 dp (Android predictive back gesture area)
        if (event.position.dx < edgeMargin ||
            event.position.dx > screenWidth - edgeMargin) {
          _canDrag = false;
        } else {
          _canDrag = true;
          _dragStartPage = _pageController.hasClients
              ? (_pageController.page?.round() ?? widget.currentIndex)
              : widget.currentIndex;
        }
      },
      onPointerUp: (_) {
        _canDrag = true;
        SwipeExclusion.isExclusionActive = false;
      },
      onPointerCancel: (_) {
        _canDrag = true;
        SwipeExclusion.isExclusionActive = false;
      },
      child: ScrollConfiguration(
        behavior: const _SwipeTabsScrollBehavior(),
        child: PageView(
          controller: _pageController,
          pageSnapping: false,
          physics: effectivePhysics,
          onPageChanged: _onPageSettled,
          children: [
            for (final child in widget.children)
              _KeepAliveTabWrapper(child: child),
          ],
        ),
      ),
    );
  }
}

/// Automatically retains state across tab swiping (scroll offset, focus, open lists).
class _KeepAliveTabWrapper extends StatefulWidget {
  final Widget child;

  const _KeepAliveTabWrapper({required this.child});

  @override
  State<_KeepAliveTabWrapper> createState() => _KeepAliveTabWrapperState();
}

class _KeepAliveTabWrapperState extends State<_KeepAliveTabWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

