import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'thought_provider.dart';
import 'database_helper.dart';
import 'navigation_service.dart';
import 'settings_service.dart';
import 'sound_service.dart';
import 'app_theme.dart';
import 'idea_detail_screen.dart';
import 'utils/title_generator.dart';
import 'widgets/keyboard_safe_sheet.dart';
import 'widgets/sticky_note_board.dart';
import 'widgets/swipe_tabs.dart';
import 'background_recording_service.dart';
import 'utils/app_toast.dart';

class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  bool _isModalOpen = false;
  bool _splitPromptChecked = false;
  int _visibleBucketIdeasCount = 20;
  int _visibleDoneCount = 9; // UPDATE 3: 9 at a time (3x3)
  int _visibleTrashCount = 12;
  String? _deletingForeverId; // For 2-step delete confirmation in Trash
  double _liveStreamPage = 0.0;

  // Sorted tab state
  bool _bucketsSectionOpen = false;
  Timer? _bucketDebounceTimer;
  final ScrollController _sortedScrollController = ScrollController();
  final GlobalKey _searchBucketsFieldKey = GlobalKey();

  // UPDATE 3: Bucket slider & search state
  String _bucketSearchQuery = '';
  final TextEditingController _bucketSearchController = TextEditingController();
  final PageController _bucketPageController = PageController();
  int _bucketCurrentPage = 0;

  // Step 3: Bucket detail search and filters state
  String? _lastSelectedBucket;
  String _bucketIdeaSearchQuery = '';
  final TextEditingController _bucketIdeaSearchController = TextEditingController();
  Timer? _bucketIdeaSearchDebounce;

  String _bucketFilterDate = 'All time'; // 'All time', 'This week', 'This month', 'Last month', 'This year', 'Pick a month'
  int? _bucketFilterMonth;
  int? _bucketFilterYear;
  bool _bucketFilterDateUnknown = false;
  String _bucketFilterSort = 'Best first'; // 'Best first', 'Newest first', 'Oldest first'
  String _bucketFilterWhen = 'Any'; // 'Any', 'Today', 'Soon', 'Later'
  String _bucketFilterTime = 'Any'; // 'Any', 'Quick', 'Medium', 'Long'

  void _resetBucketFiltersAndSearch() {
    _bucketIdeaSearchDebounce?.cancel();
    _bucketIdeaSearchController.clear();
    _bucketIdeaSearchQuery = '';
    _bucketFilterDate = 'All time';
    _bucketFilterMonth = null;
    _bucketFilterYear = null;
    _bucketFilterDateUnknown = false;
    _bucketFilterSort = 'Best first';
    _bucketFilterWhen = 'Any';
    _bucketFilterTime = 'Any';
    _visibleBucketIdeasCount = 20;
  }

  // UPDATE 3: Done search state
  String _doneSearchQuery = '';
  final TextEditingController _doneSearchController = TextEditingController();

  void _scrollToSearchBuckets() {
    final ctx = _searchBucketsFieldKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: Duration.zero,
        alignment: 0.0,
      );
    }
  }

  @override
  void dispose() {
    _bucketDebounceTimer?.cancel();
    _bucketIdeaSearchDebounce?.cancel();
    _sortedScrollController.dispose();
    _bucketSearchController.dispose();
    _bucketIdeaSearchController.dispose();
    _bucketPageController.dispose();
    _doneSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLog149Prompt();
      if (mounted) {
        final settings = context.read<SettingsService>();
        final provider = context.read<ThoughtProvider>();
        final bg = context.read<BackgroundRecordingService>();
        bg.autoRetryPendingAndFailed(settings, provider);
        bg.cleanupExpiredAudio(settings);
      }
    });
  }

  // --- LOG-149 Note Splitting Prompt (preserved) ---
  Future<void> _checkLog149Prompt() async {
    if (_splitPromptChecked) return;
    _splitPromptChecked = true;

    try {
      final box = await Hive.openBox('app_preferences');
      final alreadyPrompted =
          box.get('log149_split_prompt_shown', defaultValue: false) as bool;
      if (alreadyPrompted) return;

      if (!mounted) return;
      final provider = context.read<ThoughtProvider>();
      final log149 = provider.findLog149();
      if (log149 != null && mounted) {
        final content = (log149['content'] as String? ?? '');
        final lines =
            content.split('\n').where((l) => l.trim().isNotEmpty).toList();
        if (lines.length > 2) {
          _showSplitPromptDialog(log149, box);
        }
      }
    } catch (_) {}
  }

  void _showSplitPromptDialog(Map<String, dynamic> log149, Box box) {
    final settings = context.read<SettingsService>();
    final colors = AppColors.of(settings.theme);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.gold, width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.call_split, color: colors.gold, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Split note into separate ideas?',
                style: appFont(
                  color: colors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Your long note LOG-149 contains multiple items. Would you like to split it into individual ideas across buckets (e.g., School related, Personal revisions, Personal projects, Others\' projects)?\n\nYour original note will not be deleted.',
          style: appFont(
            color: colors.mute,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () {
              box.put('log149_split_prompt_shown', true);
              Navigator.pop(ctx);
            },
            child: Text(
              'Not now',
              style: appFont(color: colors.mute, fontSize: 15),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              box.put('log149_split_prompt_shown', true);
              Navigator.pop(ctx);
              await _performSplitLog149(log149);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: Text(
              'Split note',
              style: appFont(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performSplitLog149(Map<String, dynamic> log149) async {
    final provider = context.read<ThoughtProvider>();
    final content = log149['content'] as String? ?? '';
    final lines = content.split('\n');

    final Map<String, List<String>> bucketed = {
      'School related': [],
      'Personal revisions': [],
      'Personal projects': [],
      "Others' projects": [],
    };

    String currentBucket = 'Personal projects';
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final lower = trimmed.toLowerCase();
      if (lower.contains('school related') || lower.contains('school')) {
        currentBucket = 'School related';
      } else if (lower.contains('personal revisions') ||
          lower.contains('revision')) {
        currentBucket = 'Personal revisions';
      } else if (lower.contains('personal projects') ||
          lower.contains('personal project')) {
        currentBucket = 'Personal projects';
      } else if (lower.contains('others projects') ||
          lower.contains("others' projects")) {
        currentBucket = "Others' projects";
      } else {
        bucketed.putIfAbsent(currentBucket, () => []).add(trimmed);
      }
    }

    await provider.splitNoteIntoIdeas(log149['id'], bucketed);

    if (mounted) {
      _showUndoSnackBar('Successfully split note into separate ideas', () {});
    }
  }

  // --- Toast Notification in Bottom-Left Message Box with [X] Close & Undo ---
  void _showUndoSnackBar(String message, VoidCallback onUndo) {
    final settings = context.read<SettingsService>();
    AppToast.show(
      context,
      message: message,
      actionLabel: 'UNDO',
      onAction: () {
        SoundService.instance.play(SoundEvent.undo, settings: settings);
        onUndo();
      },
    );
  }

  // --- First-Time Sound Choice Card (Section 2) ---
  Widget _buildSoundChoiceCard(SettingsService settings, AppColors colors) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.gold.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volume_up_outlined, color: colors.gold, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add soft sounds to buttons and actions?',
                  style: appFont(
                    color: colors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 420;
              final buttons = [
                // 1. "Try a sound" (plays the Save sound)
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      SoundService.instance.play(
                        SoundEvent.save,
                        settings: settings,
                        preview: true,
                      );
                    },
                    icon: Icon(Icons.play_arrow_rounded, color: colors.gold, size: 18),
                    label: Text(
                      'Try a sound',
                      style: appFont(
                        color: colors.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.gold),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                // 2. "Turn on"
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      await settings.setSoundsEnabled(true);
                      await settings.setSoundPromptAnswered(true);
                      SoundService.instance.play(
                        SoundEvent.save,
                        settings: settings,
                        preview: true,
                      );
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Turn on',
                      style: appFont(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                // 3. "No thanks"
                SizedBox(
                  height: 48,
                  child: TextButton(
                    onPressed: () async {
                      await settings.setSoundsEnabled(false);
                      await settings.setSoundPromptAnswered(true);
                      setState(() {});
                    },
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'No thanks',
                      style: appFont(
                        color: colors.mute,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ];

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buttons[0],
                    const SizedBox(height: 8),
                    buttons[1],
                    const SizedBox(height: 4),
                    buttons[2],
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: buttons[0]),
                  const SizedBox(width: 8),
                  Expanded(child: buttons[1]),
                  const SizedBox(width: 8),
                  Expanded(child: buttons[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationNotifier>();
    final provider = context.watch<ThoughtProvider>();
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    final bool isBucketOpen = (nav.streamSubTab == 'sorted' && nav.selectedBucket != null && !nav.isTrashOpen);

    // If leaving a bucket, reset search and filters
    if (_lastSelectedBucket != null && nav.selectedBucket == null) {
      _resetBucketFiltersAndSearch();
    }
    _lastSelectedBucket = nav.selectedBucket;

    if (isBucketOpen) {
      return SafeArea(
        child: _buildBucketDetailView(
          nav,
          provider,
          settings,
          nav.selectedBucket!,
          colors,
        ),
      );
    }

    // Expanded Fullscreen Sticky Note Board (PART 1: STICKY NOTE BOARD)
    if (nav.isBoardExpanded && !nav.isTrashOpen) {
      return SafeArea(
        child: StickyNoteBoard(
          isExpandedView: true,
          onOpenSorted: () => nav.setBoardExpanded(false),
          onToggleExpand: () => nav.setBoardExpanded(false),
        ),
      );
    }

    final targetPage = nav.streamSubTab == 'unsorted' ? 1.0 : 0.0;
    if ((_liveStreamPage - targetPage).abs() > 0.01 && !nav.isTrashOpen) {
      _liveStreamPage = targetPage;
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () {
          if (nav.streamSubTab == 'sorted') {
            setState(() => _liveStreamPage = 1.0);
            nav.setStreamSubTab('unsorted');
          }
        },
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () {
          if (nav.streamSubTab == 'unsorted') {
            setState(() => _liveStreamPage = 0.0);
            nav.setStreamSubTab('sorted');
          }
        },
      },
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 8),

                // Top Navigation Bar when inside Sort View (Requirement 7)
                if (!nav.isTrashOpen) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      children: [
                        // Back to Board button (Requirement 7)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E222B),
                            foregroundColor: colors.gold,
                            elevation: 0,
                            side: BorderSide(color: colors.gold.withValues(alpha: 0.7), width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.push_pin, size: 15),
                          label: Text(
                            '← Back to Board (${provider.pinnedCount}/8)',
                            style: appFont(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: () => nav.setBoardExpanded(true),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.line),
                          ),
                          child: Text(
                            'SORT VIEW',
                            style: appFont(
                              color: colors.gold,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // First-time sound choice card (Section 2)
                if (!settings.soundPromptAnswered) ...[
                  _buildSoundChoiceCard(settings, colors),
                  const SizedBox(height: 10),
                ],
                // Top Navigation Pills: Unsorted (N) / Sorted / Done
                _buildTopPills(nav, provider, colors, settings),
                if (!(nav.streamSubTab == 'sorted' && nav.selectedBucket == null && !nav.isTrashOpen)) ...[
                  const SizedBox(height: 8),
                  _buildSubtitle(nav, colors),
                ],
                const SizedBox(height: 12),
                // Main Content Area
                Expanded(
                  child: nav.isTrashOpen
                      ? _buildTrashScreen(provider, nav, colors, settings)
                      : _buildCurrentTabContent(nav, provider, settings, colors),
                ),
              ],
            ),
            // Floating 3D Trash Button (Bottom Right)
            if (!nav.isTrashOpen &&
                MediaQuery.viewInsetsOf(context).bottom == 0 &&
                !_isModalOpen &&
                (ModalRoute.of(context)?.isCurrent ?? true))
              Positioned(
                right: 20,
                bottom: 20,
                child: _Floating3DTrashButton(
                  trashCount: provider.trashCount,
                  isOpen: nav.isTrashOpen,
                  colors: colors,
                  onTap: () {
                    setState(() => _deletingForeverId = null);
                    SoundService.instance.play(SoundEvent.tabSwitch, settings: settings);
                    nav.toggleTrash();
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --- Subtitle Widget (Plain words, sentence case) ---
  Widget _buildSubtitle(NavigationNotifier nav, AppColors colors) {
    if (nav.streamSubTab == 'sorted' && nav.selectedBucket == null && !nav.isTrashOpen) {
      return const SizedBox.shrink();
    }
    String text;
    if (nav.isTrashOpen) {
      text = 'Deleted ideas. Restore or remove forever.';
    } else {
      switch (nav.streamSubTab) {
        case 'unsorted':
          text = 'New ideas land here. File each one in a bucket.';
          break;
        case 'sorted':
          text = nav.selectedBucket == null
              ? ''
              : 'Ranked best-first based on when and time.';
          break;
        case 'done':
          text = 'Completed ideas.';
          break;
        default:
          text = 'New ideas land here. File each one in a bucket.';
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: appFont(
          color: colors.mute,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  // --- Top Navigation Pills (Min 48px height touch target) ---
  Widget _buildTopPills(
    NavigationNotifier nav,
    ThoughtProvider provider,
    AppColors colors,
    SettingsService settings,
  ) {
    final unsortedCount = provider.unsortedCount;
    final currentSubTab = nav.streamSubTab;
    final isTrashOpen = nav.isTrashOpen;

    final liveIndex = _liveStreamPage.round().clamp(0, 1);
    final isSortedSelected = !isTrashOpen && liveIndex == 0;
    final isUnsortedSelected = !isTrashOpen && liveIndex == 1;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && liveIndex == 0) {
            setState(() => _liveStreamPage = 1.0);
            nav.setStreamSubTab('unsorted');
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && liveIndex == 1) {
            setState(() => _liveStreamPage = 0.0);
            nav.setStreamSubTab('sorted');
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Sorted tab first
          _buildPill(
            label: 'Sorted',
            semanticsLabel: 'Sorted, tab 1 of 2${isSortedSelected ? ', selected' : ''}',
            isSelected: isSortedSelected,
            colors: colors,
            onTap: () {
              setState(() => _liveStreamPage = 0.0);
              if (currentSubTab != 'sorted' || isTrashOpen) {
                SoundService.instance.play(SoundEvent.tabSwitch, settings: settings);
              }
              nav.setStreamSubTab('sorted');
            },
          ),
          const SizedBox(width: 8),
          // Unsorted with count
          _buildPill(
            label: 'Unsorted ($unsortedCount)',
            semanticsLabel: 'Unsorted ($unsortedCount), tab 2 of 2${isUnsortedSelected ? ', selected' : ''}',
            isSelected: isUnsortedSelected,
            colors: colors,
            onTap: () {
              setState(() => _liveStreamPage = 1.0);
              if (currentSubTab != 'unsorted' || isTrashOpen) {
                SoundService.instance.play(SoundEvent.tabSwitch, settings: settings);
              }
              nav.setStreamSubTab('unsorted');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required String semanticsLabel,
    required bool isSelected,
    required AppColors colors,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? colors.goldBg : colors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? colors.gold : colors.line,
                width: isSelected ? 1.8 : 1.0,
              ),
            ),
            child: Text(
              label,
              style: appFont(
                color: isSelected ? colors.gold : colors.text,
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Main Content Switcher with SwipeTabs ---
  Widget _buildCurrentTabContent(
    NavigationNotifier nav,
    ThoughtProvider provider,
    SettingsService settings,
    AppColors colors,
  ) {
    final int currentIndex = nav.streamSubTab == 'unsorted' ? 1 : 0;
    BackgroundRecordingService? bgRecording;
    try {
      bgRecording = context.watch<BackgroundRecordingService>();
    } catch (_) {}
    final isRecording = bgRecording?.isRecording ?? false;

    return SwipeTabs(
      currentIndex: currentIndex,
      tabLabels: const ['Sorted', 'Unsorted'],
      thresholdFraction: settings.swipeThresholdFraction,
      enabled: settings.swipeSortedUnsorted &&
          nav.selectedBucket == null &&
          !nav.isTrashOpen &&
          !_isModalOpen &&
          !isRecording &&
          MediaQuery.viewInsetsOf(context).bottom == 0,
      isRecording: isRecording,
      onDragProgress: (page) {
        if ((page - _liveStreamPage).abs() > 0.05) {
          setState(() => _liveStreamPage = page);
        }
      },
      onTabChanged: (index) {
        setState(() => _liveStreamPage = index.toDouble());
        nav.setStreamSubTab(index == 0 ? 'sorted' : 'unsorted');
      },
      children: [
        _buildSortedTab(nav, provider, settings, colors),
        _buildUnsortedTab(provider, nav, colors),
      ],
    );
  }

  // ==========================================================================
  // TAB 1: UNSORTED TAB (Section 3: ONE idea at a time)
  // ==========================================================================
  Widget _buildUnsortedTab(
    ThoughtProvider provider,
    NavigationNotifier nav,
    AppColors colors,
  ) {
    final unsorted = provider.unsortedThoughts;

    if (unsorted.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, size: 64, color: colors.done),
              const SizedBox(height: 16),
              Text(
                'All caught up!',
                style: appFont(
                  color: colors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No unsorted ideas right now.\nCapture new ideas using voice or text below.',
                textAlign: TextAlign.center,
                style: appFont(color: colors.mute, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => nav.setStreamSubTab('sorted'),
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: const Text('Go to Sorted ideas'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final thought = unsorted.first;
    final totalCount = unsorted.length;
    final isDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
        MediaQuery.of(context).size.width >= 600;
    final settings = context.watch<SettingsService>();
    final ideaName = TitleGenerator.getIdeaName(thought);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Help line: "Idea 1 of Y. Pick a bucket for it." (Reserved fixed height: 32px)
          SizedBox(
            height: 32,
            child: Center(
              child: Text(
                'Idea 1 of $totalCount. Pick a bucket for it.',
                textAlign: TextAlign.center,
                style: appFont(
                  color: colors.gold,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // The Fixed-Size Idea Card (220px desktop, 200px phone)
          SizedBox(
            height: isDesktop ? 220.0 : 200.0,
            child: settings.swipeActionsOnIdeas
                ? Dismissible(
                    key: ValueKey('unsorted_dismissible_${thought['id']}'),
                    direction: DismissDirection.horizontal,
                    dismissThresholds: const {
                      DismissDirection.startToEnd: 0.40,
                      DismissDirection.endToStart: 0.40,
                    },
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: colors.gold,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.folder, color: Colors.black, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'Choose bucket',
                            style: appFont(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    secondaryBackground: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: colors.card,
                        border: Border.all(color: colors.line),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Skip for now',
                            style: appFont(
                              color: colors.gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.skip_next, color: colors.gold, size: 24),
                        ],
                      ),
                    ),
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        SoundService.instance.play(SoundEvent.popupOpen, settings: settings);
                        _showChooseBucketPopup(
                          context: context,
                          provider: provider,
                          idea: thought,
                          colors: colors,
                          heading: 'Choose a bucket',
                        );
                        return false;
                      } else if (direction == DismissDirection.endToStart) {
                        final thoughtId = thought['id'];
                        provider.skipThoughtForSession(thoughtId);
                        _showUndoSnackBar('Skipped "$ideaName" for now', () {
                          provider.unskipThought(thoughtId);
                        });
                        return true;
                      }
                      return false;
                    },
                    child: FixedIdeaCard(
                      idea: thought,
                      colors: colors,
                      provider: provider,
                      isDesktop: isDesktop,
                      onReadMore: () => _showReadMorePopup(
                        context: context,
                        idea: thought,
                        provider: provider,
                        colors: colors,
                        settings: settings,
                      ),
                      onMoreOptions: () =>
                          _showIdeaContextMenu(context, provider, thought, colors),
                    ),
                  )
                : FixedIdeaCard(
                    idea: thought,
                    colors: colors,
                    provider: provider,
                    isDesktop: isDesktop,
                    onReadMore: () => _showReadMorePopup(
                      context: context,
                      idea: thought,
                      provider: provider,
                      colors: colors,
                      settings: settings,
                    ),
                    onMoreOptions: () =>
                        _showIdeaContextMenu(context, provider, thought, colors),
                  ),
          ),
          const SizedBox(height: 16),

          // Primary Action: [Choose a bucket] (Fixed height 48px)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _showChooseBucketPopup(
                context: context,
                provider: provider,
                idea: thought,
                colors: colors,
                heading: 'Choose a bucket',
              ),
              icon: const Icon(Icons.folder_outlined,
                  color: Colors.black, size: 20),
              label: Text(
                'Choose a bucket',
                style: appFont(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Secondary Actions: [Skip for now] and [Trash] (Fixed height 48px)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      provider.skipThoughtForSession(thought['id']);
                      setState(() {});
                    },
                    icon: Icon(Icons.arrow_forward,
                        size: 18, color: colors.mute),
                    label: Text(
                      'Skip for now',
                      style: appFont(
                        color: colors.mute,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      provider.moveToTrash(thought['id']);
                      SoundService.instance.play(SoundEvent.trash, settings: settings);
                      _showUndoSnackBar(
                        'Moved "$ideaName" to trash',
                        () => provider.restoreFromTrash(thought['id']),
                      );
                      setState(() {});
                    },
                    icon: Icon(Icons.delete_outline,
                        size: 18, color: colors.bad),
                    label: Text(
                      'Trash',
                      style: appFont(
                        color: colors.bad,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.bad.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // TAB 2: SORTED TAB (Step 1 Redesign)
  // ==========================================================================
  Widget _buildSortedTab(
    NavigationNotifier nav,
    ThoughtProvider provider,
    SettingsService settings,
    AppColors colors,
  ) {
    if (nav.selectedBucket != null) {
      return _buildBucketDetailView(
          nav, provider, settings, nav.selectedBucket!, colors);
    }

    final isDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
        MediaQuery.of(context).size.width >= 600;

    final sorted = provider.sortedThoughts;
    final best = provider.bestNextThought;
    final orderedBuckets = provider.getOrderedBuckets(settings.bucketOrder);

    // If nothing sorted yet: show "Nothing sorted yet. File an idea from Unsorted to begin." with "Go to Unsorted" button.
    // If there are no buckets, hide the "View buckets" button.
    if (sorted.isEmpty) {
      return ListView(
        key: const PageStorageKey('sorted_scroll_view_empty'),
        controller: _sortedScrollController,
        padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              children: [
                Icon(Icons.folder_open, size: 56, color: colors.mute),
                const SizedBox(height: 14),
                Text(
                  'Nothing sorted yet. File an idea from Unsorted to begin.',
                  textAlign: TextAlign.center,
                  style: appFont(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: () => nav.setStreamSubTab('unsorted'),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Go to Unsorted'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (orderedBuckets.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildViewBucketsButton(
              bucketCount: orderedBuckets.length,
              isOpen: _bucketsSectionOpen,
              colors: colors,
              onTap: () {
                setState(() {
                  _bucketsSectionOpen = !_bucketsSectionOpen;
                });
                if (_bucketsSectionOpen) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToSearchBuckets();
                  });
                }
              },
            ),
            if (_bucketsSectionOpen) ...[
              const SizedBox(height: 14),
              _buildBucketsSection(
                nav,
                provider,
                settings,
                orderedBuckets,
                colors,
              ),
            ],
          ],
        ],
      );
    }

    // Default view: Sorted shows ONLY: the pills, then the "Start here" card, then one button.
    return ListView(
      key: const PageStorageKey('sorted_scroll_view'),
      controller: _sortedScrollController,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      children: [
        if (best != null) ...[
          _buildStartHereCard(best, provider, settings, colors, isDesktop),
          const SizedBox(height: 16),
        ],
        if (orderedBuckets.isNotEmpty) ...[
          _buildViewBucketsButton(
            bucketCount: orderedBuckets.length,
            isOpen: _bucketsSectionOpen,
            colors: colors,
            onTap: () {
              setState(() {
                _bucketsSectionOpen = !_bucketsSectionOpen;
              });
              if (_bucketsSectionOpen) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToSearchBuckets();
                });
              }
            },
          ),
          if (_bucketsSectionOpen) ...[
            const SizedBox(height: 14),
            _buildBucketsSection(
              nav,
              provider,
              settings,
              orderedBuckets,
              colors,
            ),
          ],
        ],
      ],
    );
  }

  // --- Full-width 56px View/Hide Buckets Button ---
  Widget _buildViewBucketsButton({
    required int bucketCount,
    required bool isOpen,
    required AppColors colors,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: colors.card,
          side: BorderSide(color: colors.line, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isOpen ? 'Hide buckets' : 'View buckets ($bucketCount)',
              style: appFont(
                color: colors.text,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            Icon(
              isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: colors.gold,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  // --- Revealed Buckets Section (Search + 2-at-a-time Slider) ---
  Widget _buildBucketsSection(
    NavigationNotifier nav,
    ThoughtProvider provider,
    SettingsService settings,
    List<Map<String, dynamic>> orderedBuckets,
    AppColors colors,
  ) {
    final matchingBuckets = orderedBuckets.where((b) {
      if (_bucketSearchQuery.isEmpty) return true;
      final name = (b['name'] as String).toLowerCase();
      return name.contains(_bucketSearchQuery.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 52px Search Buckets field (filters bucket NAMES only, case-insensitive, 150ms debounce)
        SwipeExclusion(
          child: Container(
            key: _searchBucketsFieldKey,
            height: 52,
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: TextField(
            controller: _bucketSearchController,
            onChanged: (val) {
              _bucketDebounceTimer?.cancel();
              _bucketDebounceTimer =
                  Timer(const Duration(milliseconds: 150), () {
                if (mounted) {
                  setState(() {
                    _bucketSearchQuery = val.trim();
                    _bucketCurrentPage = 0;
                  });
                  if (_bucketPageController.hasClients) {
                    _bucketPageController.jumpToPage(0);
                  }
                }
              });
            },
            style: appFont(color: colors.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search buckets...',
              hintStyle: appFont(color: colors.mute, fontSize: 14),
              prefixIcon: Icon(Icons.search, color: colors.mute, size: 20),
              suffixIcon: _bucketSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, color: colors.mute, size: 18),
                      onPressed: () {
                        _bucketDebounceTimer?.cancel();
                        _bucketSearchController.clear();
                        setState(() {
                          _bucketSearchQuery = '';
                          _bucketCurrentPage = 0;
                        });
                        if (_bucketPageController.hasClients) {
                          _bucketPageController.jumpToPage(0);
                        }
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),

        // 2-at-a-time Slider
        Builder(
          builder: (ctx) {
            final List<Widget> cards = [];
            for (final b in matchingBuckets) {
              final bucketName = b['name'] as String;
              final iconKey = (b['icon'] as String?) ?? 'folder';
              final iconData = kBucketIcons[iconKey] ?? Icons.folder_outlined;
              final count = provider.getIdeaCountForBucket(bucketName);

              cards.add(
                GestureDetector(
                  onSecondaryTap: () => _showBucketContextMenu(
                      context, provider, bucketName, iconKey, count, colors),
                  onLongPress: () => _showBucketContextMenu(
                      context, provider, bucketName, iconKey, count, colors),
                  child: InkWell(
                    onTap: () => nav.selectBucket(bucketName),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.line, width: 1.2),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(iconData, size: 28, color: colors.gold),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    bucketName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: appFont(
                                      color: colors.text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$count ${count == 1 ? 'idea' : 'ideas'}',
                                    style: appFont(
                                        color: colors.mute, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: IconButton(
                              icon: Icon(Icons.more_horiz,
                                  color: colors.mute, size: 20),
                              onPressed: () => _showBucketContextMenu(
                                  context,
                                  provider,
                                  bucketName,
                                  iconKey,
                                  count,
                                  colors),
                              tooltip: 'Bucket options',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            // NOTE: NO bucket creation anywhere on this page!

            if (cards.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.line),
                ),
                child: Center(
                  child: Text(
                    'No buckets found matching "$_bucketSearchQuery"',
                    style: appFont(color: colors.mute, fontSize: 14),
                  ),
                ),
              );
            }

            final int pageCount = (cards.length / 2).ceil();
            final safeCurrentPage = _bucketCurrentPage.clamp(0, pageCount - 1);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Slider navigation controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      cards.length == 1
                          ? 'Showing 1 of 1'
                          : 'Showing ${safeCurrentPage * 2 + 1}-${math.min((safeCurrentPage + 1) * 2, cards.length)} of ${cards.length}',
                      style: appFont(color: colors.mute, fontSize: 12),
                    ),
                    if (pageCount > 1)
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.arrow_back_ios_new,
                              size: 16,
                              color: safeCurrentPage > 0
                                  ? colors.gold
                                  : colors.mute.withValues(alpha: 0.3),
                            ),
                            onPressed: safeCurrentPage > 0
                                ? () {
                                    _bucketPageController.previousPage(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            tooltip: 'Previous',
                          ),
                          Text(
                            '${safeCurrentPage + 1} / $pageCount',
                            style: appFont(
                              color: colors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: safeCurrentPage < pageCount - 1
                                  ? colors.gold
                                  : colors.mute.withValues(alpha: 0.3),
                            ),
                            onPressed: safeCurrentPage < pageCount - 1
                                ? () {
                                    _bucketPageController.nextPage(
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                : null,
                            tooltip: 'Next',
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                // 2-at-a-time Slider
                SizedBox(
                  height: 135,
                  child: SwipeExclusion(
                    child: PageView.builder(
                      controller: _bucketPageController,
                      onPageChanged: (idx) {
                        SoundService.instance.play(SoundEvent.swipe, settings: settings);
                        setState(() => _bucketCurrentPage = idx);
                      },
                      itemCount: pageCount,
                      itemBuilder: (ctx, pageIndex) {
                        final firstIndex = pageIndex * 2;
                        final secondIndex = firstIndex + 1;

                        return Row(
                          children: [
                            Expanded(child: cards[firstIndex]),
                            const SizedBox(width: 12),
                            Expanded(
                              child: secondIndex < cards.length
                                  ? cards[secondIndex]
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                if (pageCount > 1) ...[
                  const SizedBox(height: 10),
                  // Dots indicator
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(pageCount, (dotIndex) {
                      final isActive = dotIndex == safeCurrentPage;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: isActive ? 14 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive ? colors.gold : colors.line,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  // --- Top "Start here" Card for Sorted View ---
  Widget _buildStartHereCard(
    Map<String, dynamic> thought,
    ThoughtProvider provider,
    SettingsService settings,
    AppColors colors,
    bool isDesktop,
  ) {
    return SortedIdeaCard(
      idea: thought,
      colors: colors,
      provider: provider,
      settings: settings,
      isStartHere: true,
      isDesktop: isDesktop,
      onReadMore: () => _showReadMorePopup(
        context: context,
        idea: thought,
        provider: provider,
        colors: colors,
        settings: settings,
      ),
      onMoreOptions: () => _showIdeaContextMenu(
        context,
        provider,
        thought,
        colors,
      ),
      onMarkDone: () {
        final ideaName = TitleGenerator.getIdeaName(thought);
        provider.markDone(thought['id'], true);
        SoundService.instance.play(SoundEvent.done, settings: settings);
        _showUndoSnackBar('Marked "$ideaName" as done', () {
          provider.markDone(thought['id'], false);
        });
      },
    );
  }

  // ==========================================================================
  // STEP 3: THE BUCKET PAGE (FOCUS MODE)
  // ==========================================================================

  static const List<String> _kMonthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  static bool _isPlaceholderIdea(Map<String, dynamic> idea) {
    final raw = idea['created_at'];
    if (raw == null) return true;
    final val = (raw as num).toInt();
    if (val <= 0) return true;
    final cutoff = DateTime(2024, 1, 2).millisecondsSinceEpoch;
    return val < cutoff;
  }

  static List<Map<String, dynamic>> _applyBucketFilters({
    required List<Map<String, dynamic>> allIdeas,
    required String searchQuery,
    required String date,
    required int? month,
    required int? year,
    required bool dateUnknown,
    required String sort,
    required String when,
    required String time,
  }) {
    var list = List<Map<String, dynamic>>.from(allIdeas);

    // 1. Search Query: matches idea name and text, any word, case-insensitive
    if (searchQuery.isNotEmpty) {
      final words = searchQuery
          .toLowerCase()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      if (words.isNotEmpty) {
        list = list.where((idea) {
          final name = TitleGenerator.getIdeaName(idea).toLowerCase();
          final text = (idea['text'] as String? ?? '').toLowerCase();
          final full = '$name $text';
          return words.any((w) => full.contains(w));
        }).toList();
      }
    }

    // 2. Date Filter
    if (date != 'All time') {
      if (dateUnknown) {
        list = list.where(_isPlaceholderIdea).toList();
      } else if (date == 'This week') {
        final now = DateTime.now();
        final startOfWeek = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        final endOfWeek = startOfWeek.add(const Duration(days: 7));
        list = list.where((idea) {
          if (_isPlaceholderIdea(idea)) return false;
          final dt = DateTime.fromMillisecondsSinceEpoch(
                  (idea['created_at'] as num).toInt())
              .toLocal();
          return (dt.isAfter(startOfWeek) ||
                  dt.isAtSameMomentAs(startOfWeek)) &&
              dt.isBefore(endOfWeek);
        }).toList();
      } else if (date == 'This month') {
        final now = DateTime.now();
        list = list.where((idea) {
          if (_isPlaceholderIdea(idea)) return false;
          final dt = DateTime.fromMillisecondsSinceEpoch(
                  (idea['created_at'] as num).toInt())
              .toLocal();
          return dt.year == now.year && dt.month == now.month;
        }).toList();
      } else if (date == 'Last month') {
        final now = DateTime.now();
        final lmYear = now.month == 1 ? now.year - 1 : now.year;
        final lmMonth = now.month == 1 ? 12 : now.month - 1;
        list = list.where((idea) {
          if (_isPlaceholderIdea(idea)) return false;
          final dt = DateTime.fromMillisecondsSinceEpoch(
                  (idea['created_at'] as num).toInt())
              .toLocal();
          return dt.year == lmYear && dt.month == lmMonth;
        }).toList();
      } else if (date == 'This year') {
        final now = DateTime.now();
        list = list.where((idea) {
          if (_isPlaceholderIdea(idea)) return false;
          final dt = DateTime.fromMillisecondsSinceEpoch(
                  (idea['created_at'] as num).toInt())
              .toLocal();
          return dt.year == now.year;
        }).toList();
      } else if (date == 'Pick a month') {
        if (month != null && year != null) {
          list = list.where((idea) {
            if (_isPlaceholderIdea(idea)) return false;
            final dt = DateTime.fromMillisecondsSinceEpoch(
                    (idea['created_at'] as num).toInt())
                .toLocal();
            return dt.year == year && dt.month == month;
          }).toList();
        }
      }
    }

    // 3. When Filter
    if (when != 'Any') {
      list = list.where((idea) {
        final val = (idea['when_val'] as String? ?? '').toLowerCase();
        return val == when.toLowerCase();
      }).toList();
    }

    // 4. Time Filter
    if (time != 'Any') {
      list = list.where((idea) {
        final val = (idea['time_val'] as String? ?? '').toLowerCase();
        return val == time.toLowerCase();
      }).toList();
    }

    // 5. Sort
    if (sort == 'Best first') {
      list.sort(RankingEngine.compareRanked);
    } else if (sort == 'Newest first') {
      list.sort((a, b) {
        final int cA = (a['created_at'] as num?)?.toInt() ?? 0;
        final int cB = (b['created_at'] as num?)?.toInt() ?? 0;
        return cB.compareTo(cA);
      });
    } else if (sort == 'Oldest first') {
      list.sort((a, b) {
        final int cA = (a['created_at'] as num?)?.toInt() ?? 0;
        final int cB = (b['created_at'] as num?)?.toInt() ?? 0;
        if (cA <= 0 && cB > 0) return 1;
        if (cB <= 0 && cA > 0) return -1;
        return cA.compareTo(cB);
      });
    }

    return list;
  }

  Widget _buildBucketDetailView(
    NavigationNotifier nav,
    ThoughtProvider provider,
    SettingsService settings,
    String bucketName,
    AppColors colors,
  ) {
    final allIdeas = provider.getThoughtsForBucket(bucketName);
    final int totalBucketIdeas = allIdeas.length;
    final iconKey = provider.getBucketIcon(bucketName);
    final iconData = kBucketIcons[iconKey] ?? Icons.folder_outlined;
    final isDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
        MediaQuery.of(context).size.width >= 600;

    final filteredIdeas = _applyBucketFilters(
      allIdeas: allIdeas,
      searchQuery: _bucketIdeaSearchQuery,
      date: _bucketFilterDate,
      month: _bucketFilterMonth,
      year: _bucketFilterYear,
      dateUnknown: _bucketFilterDateUnknown,
      sort: _bucketFilterSort,
      when: _bucketFilterWhen,
      time: _bucketFilterTime,
    );

    final int visibleCount =
        math.min(_visibleBucketIdeasCount, filteredIdeas.length);
    final visibleIdeas = filteredIdeas.take(visibleCount).toList();

    int activeFilterCount = 0;
    if (_bucketFilterDate != 'All time') activeFilterCount++;
    if (_bucketFilterSort != 'Best first') activeFilterCount++;
    if (_bucketFilterWhen != 'Any') activeFilterCount++;
    if (_bucketFilterTime != 'Any') activeFilterCount++;

    final activeChips = <Widget>[];

    if (_bucketFilterDate != 'All time') {
      String dateLabel = _bucketFilterDate;
      if (_bucketFilterDateUnknown) {
        dateLabel = 'Date: Unknown';
      } else if (_bucketFilterDate == 'Pick a month' &&
          _bucketFilterMonth != null &&
          _bucketFilterYear != null) {
        dateLabel =
            'Date: ${_kMonthNames[_bucketFilterMonth! - 1]} $_bucketFilterYear';
      } else {
        dateLabel = 'Date: $_bucketFilterDate';
      }
      activeChips.add(
        Chip(
          label: Text(
            dateLabel,
            style: appFont(color: colors.text, fontSize: 12),
          ),
          deleteIcon: Icon(Icons.close, size: 14, color: colors.mute),
          onDeleted: () {
            setState(() {
              _bucketFilterDate = 'All time';
              _bucketFilterMonth = null;
              _bucketFilterYear = null;
              _bucketFilterDateUnknown = false;
            });
          },
          backgroundColor: colors.card,
          side: BorderSide(color: colors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    if (_bucketFilterSort != 'Best first') {
      activeChips.add(
        Chip(
          label: Text(
            'Sort: $_bucketFilterSort',
            style: appFont(color: colors.text, fontSize: 12),
          ),
          deleteIcon: Icon(Icons.close, size: 14, color: colors.mute),
          onDeleted: () {
            setState(() => _bucketFilterSort = 'Best first');
          },
          backgroundColor: colors.card,
          side: BorderSide(color: colors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    if (_bucketFilterWhen != 'Any') {
      activeChips.add(
        Chip(
          label: Text(
            'When: $_bucketFilterWhen',
            style: appFont(color: colors.text, fontSize: 12),
          ),
          deleteIcon: Icon(Icons.close, size: 14, color: colors.mute),
          onDeleted: () {
            setState(() => _bucketFilterWhen = 'Any');
          },
          backgroundColor: colors.card,
          side: BorderSide(color: colors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    if (_bucketFilterTime != 'Any') {
      activeChips.add(
        Chip(
          label: Text(
            'Time: $_bucketFilterTime',
            style: appFont(color: colors.text, fontSize: 12),
          ),
          deleteIcon: Icon(Icons.close, size: 14, color: colors.mute),
          onDeleted: () {
            setState(() => _bucketFilterTime = 'Any');
          },
          backgroundColor: colors.card,
          side: BorderSide(color: colors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    final String resultLine = filteredIdeas.length > visibleCount
        ? 'Showing $visibleCount of ${filteredIdeas.length}'
        : '${filteredIdeas.length} ${filteredIdeas.length == 1 ? 'idea matches' : 'ideas match'}';

    return ListView(
      padding:
          const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 40),
      children: [
        // Top of page: "‹ All buckets" (48px touch target at very top)
        Semantics(
          button: true,
          label: '‹ All buckets',
          child: InkWell(
            onTap: () {
              _resetBucketFiltersAndSearch();
              nav.selectBucket(null);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              constraints: const BoxConstraints(minHeight: 48),
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, color: colors.gold, size: 24),
                  const SizedBox(width: 4),
                  Text(
                    'All buckets',
                    style: appFont(
                      color: colors.gold,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Bucket icon, name and "48 ideas"
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(iconData, size: 26, color: colors.gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      bucketName,
                      style: appFont(
                        color: colors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.line),
              ),
              child: Text(
                '$totalBucketIdeas ${totalBucketIdeas == 1 ? 'idea' : 'ideas'}',
                style: appFont(
                  color: colors.mute,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Search & Filter Row directly under header BEFORE any ideas
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.line),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: _bucketIdeaSearchController,
                    onChanged: (val) {
                      _bucketIdeaSearchDebounce?.cancel();
                      _bucketIdeaSearchDebounce =
                          Timer(const Duration(milliseconds: 200), () {
                        if (mounted) {
                          setState(() {
                            _bucketIdeaSearchQuery = val.trim();
                            _visibleBucketIdeasCount = 20;
                          });
                        }
                      });
                    },
                    style: appFont(color: colors.text, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Search this bucket...',
                      hintStyle: appFont(color: colors.mute, fontSize: 14),
                      prefixIcon:
                          Icon(Icons.search, color: colors.mute, size: 20),
                      suffixIcon: _bucketIdeaSearchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.close,
                                  color: colors.mute, size: 18),
                              onPressed: () {
                                _bucketIdeaSearchDebounce?.cancel();
                                _bucketIdeaSearchController.clear();
                                setState(() {
                                  _bucketIdeaSearchQuery = '';
                                  _visibleBucketIdeasCount = 20;
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  _showBucketFilterSheet(context, allIdeas, colors, isDesktop);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      activeFilterCount > 0 ? colors.gold : colors.card,
                  foregroundColor:
                      activeFilterCount > 0 ? Colors.black : colors.text,
                  side: BorderSide(
                    color: activeFilterCount > 0 ? colors.gold : colors.line,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune,
                      size: 18,
                      color: activeFilterCount > 0 ? Colors.black : colors.mute,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Filter',
                      style: appFont(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color:
                            activeFilterCount > 0 ? Colors.black : colors.text,
                      ),
                    ),
                    if (activeFilterCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$activeFilterCount',
                          style: appFont(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),

        // Active filters chips row
        if (activeChips.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...activeChips,
              TextButton(
                onPressed: () {
                  setState(() {
                    _resetBucketFiltersAndSearch();
                  });
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Clear filters',
                  style: appFont(
                    color: colors.gold,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],

        // Result line: "Showing 20 of 48" or "12 ideas match"
        const SizedBox(height: 12),
        Text(
          resultLine,
          style: appFont(
            color: colors.mute,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Ideas or Empty result
        if (filteredIdeas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search_off, size: 48, color: colors.mute),
                  const SizedBox(height: 12),
                  Text(
                    'No ideas match.',
                    style: appFont(
                      color: colors.mute,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _resetBucketFiltersAndSearch();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.card,
                      foregroundColor: colors.gold,
                      side: BorderSide(color: colors.line),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Clear filters',
                      style: appFont(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          ...visibleIdeas.asMap().entries.map((entry) {
            final int index = entry.key;
            final Map<String, dynamic> idea = entry.value;
            final bool isFirst =
                (index == 0 && _bucketFilterSort == 'Best first');

            return _buildRankedIdeaCard(
              idea: idea,
              isFirst: isFirst,
              provider: provider,
              colors: colors,
              settings: settings,
              isDesktop: isDesktop,
            );
          }),
          // Pagination: "Show more" button if more ideas exist
          if (filteredIdeas.length > visibleCount) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  setState(() => _visibleBucketIdeasCount += 20);
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.gold, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Show more',
                  style: appFont(
                    color: colors.gold,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  void _showBucketFilterSheet(
    BuildContext context,
    List<Map<String, dynamic>> allIdeas,
    AppColors colors,
    bool isDesktop,
  ) {
    if (isDesktop) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: colors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.line),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
            child: _BucketFilterContent(
              allIdeas: allIdeas,
              searchQuery: _bucketIdeaSearchQuery,
              initialDate: _bucketFilterDate,
              initialMonth: _bucketFilterMonth,
              initialYear: _bucketFilterYear,
              initialDateUnknown: _bucketFilterDateUnknown,
              initialSort: _bucketFilterSort,
              initialWhen: _bucketFilterWhen,
              initialTime: _bucketFilterTime,
              colors: colors,
              onApply: ({
                required String date,
                required int? month,
                required int? year,
                required bool dateUnknown,
                required String sort,
                required String when,
                required String time,
              }) {
                setState(() {
                  _bucketFilterDate = date;
                  _bucketFilterMonth = month;
                  _bucketFilterYear = year;
                  _bucketFilterDateUnknown = dateUnknown;
                  _bucketFilterSort = sort;
                  _bucketFilterWhen = when;
                  _bucketFilterTime = time;
                  _visibleBucketIdeasCount = 20;
                });
              },
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: colors.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: _BucketFilterContent(
            allIdeas: allIdeas,
            searchQuery: _bucketIdeaSearchQuery,
            initialDate: _bucketFilterDate,
            initialMonth: _bucketFilterMonth,
            initialYear: _bucketFilterYear,
            initialDateUnknown: _bucketFilterDateUnknown,
            initialSort: _bucketFilterSort,
            initialWhen: _bucketFilterWhen,
            initialTime: _bucketFilterTime,
            colors: colors,
            onApply: ({
              required String date,
              required int? month,
              required int? year,
              required bool dateUnknown,
              required String sort,
              required String when,
              required String time,
            }) {
              setState(() {
                _bucketFilterDate = date;
                _bucketFilterMonth = month;
                _bucketFilterYear = year;
                _bucketFilterDateUnknown = dateUnknown;
                _bucketFilterSort = sort;
                _bucketFilterWhen = when;
                _bucketFilterTime = time;
                _visibleBucketIdeasCount = 20;
              });
            },
          ),
        ),
      );
    }
  }


  // --- Ranked Idea Card in Drill-Down Bucket View (Step 2: Shared Idea Card) ---
  Widget _buildRankedIdeaCard({
    required Map<String, dynamic> idea,
    required bool isFirst,
    required ThoughtProvider provider,
    required AppColors colors,
    required SettingsService settings,
    required bool isDesktop,
  }) {
    final ideaName = TitleGenerator.getIdeaName(idea);

    final cardWidget = SortedIdeaCard(
      idea: idea,
      colors: colors,
      provider: provider,
      settings: settings,
      isStartHere: isFirst,
      isDesktop: isDesktop,
      onReadMore: () => _showReadMorePopup(
        context: context,
        idea: idea,
        provider: provider,
        colors: colors,
        settings: settings,
      ),
      onMoreOptions: () =>
          _showIdeaContextMenu(context, provider, idea, colors),
      onMarkDone: () {
        provider.markDone(idea['id'], true);
        SoundService.instance.play(SoundEvent.done, settings: settings);
        _showUndoSnackBar('Marked "$ideaName" as done', () {
          provider.markDone(idea['id'], false);
        });
      },
    );

    if (settings.swipeActionsOnIdeas) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        child: Dismissible(
          key: ValueKey('ranked_idea_${idea['id']}'),
          direction: DismissDirection.horizontal,
          dismissThresholds: const {
            DismissDirection.startToEnd: 0.40,
            DismissDirection.endToStart: 0.40,
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: colors.done,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.black, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Mark done',
                  style: appFont(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: colors.bad,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Move to Trash',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.delete, color: Colors.white, size: 24),
              ],
            ),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              provider.markDone(idea['id'], true);
              SoundService.instance.play(SoundEvent.done, settings: settings);
              _showUndoSnackBar('Marked "$ideaName" as done', () {
                provider.markDone(idea['id'], false);
              });
              return true;
            } else if (direction == DismissDirection.endToStart) {
              provider.moveToTrash(idea['id']);
              SoundService.instance.play(SoundEvent.trash, settings: settings);
              _showUndoSnackBar('Moved "$ideaName" to trash', () {
                provider.restoreFromTrash(idea['id']);
              });
              return true;
            }
            return false;
          },
          child: cardWidget,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: cardWidget,
    );
  }

  // ==========================================================================
  // TAB 3: DONE TAB (Section 5: Green File Icons Grid + Peek Sheet)
  // ==========================================================================
  // ignore: unused_element
  Widget _buildDoneTab(ThoughtProvider provider, AppColors colors) {
    final doneList = provider.doneThoughts;

    if (doneList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.task_alt, size: 64, color: colors.mute),
              const SizedBox(height: 16),
              Text(
                'No completed ideas yet',
                style: appFont(
                  color: colors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap the "Mark done" button on any idea to file it here.',
                textAlign: TextAlign.center,
                style: appFont(color: colors.mute, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    final filteredDone = doneList.where((t) {
      if (_doneSearchQuery.isEmpty) return true;
      final q = _doneSearchQuery.toLowerCase();
      final title = (t['title'] as String? ?? '').toLowerCase();
      final content = (t['content'] as String? ?? '').toLowerCase();
      final id = (t['thought_id'] as String? ?? '').toLowerCase();
      final bucket = (t['bucket'] as String? ?? '').toLowerCase();
      return title.contains(q) || content.contains(q) || id.contains(q) || bucket.contains(q);
    }).toList();

    final visibleCount = math.min(_visibleDoneCount, filteredDone.length);
    final visibleDone = filteredDone.take(visibleCount).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search Bar for Done (Section A.3)
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: TextField(
              controller: _doneSearchController,
              onChanged: (val) {
                setState(() {
                  _doneSearchQuery = val.trim();
                  _visibleDoneCount = 9;
                });
              },
              style: appFont(color: colors.text, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search completed ideas...',
                hintStyle: appFont(color: colors.mute, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: colors.mute, size: 20),
                suffixIcon: _doneSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, color: colors.mute, size: 18),
                        onPressed: () {
                          _doneSearchController.clear();
                          setState(() {
                            _doneSearchQuery = '';
                            _visibleDoneCount = 9;
                          });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Count Header: "38 done. Tap a file to peek inside."
          Text(
            _doneSearchQuery.isEmpty
                ? '${doneList.length} done. Tap a file to peek inside.'
                : '${filteredDone.length} of ${doneList.length} done matching search',
            textAlign: TextAlign.center,
            style: appFont(
              color: colors.mute,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),

          if (filteredDone.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(28.0),
              child: Center(
                child: Text(
                  'No completed ideas match "$_doneSearchQuery"',
                  style: appFont(color: colors.mute, fontSize: 15),
                ),
              ),
            ),
          ] else ...[
            // 9 at a time (3 x 3) Grid (Section A.3)
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleDone.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, // 3 x 3 grid (3 columns)
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.95,
              ),
              itemBuilder: (context, index) {
                final thought = visibleDone[index];
                final content = (thought['content'] as String? ?? '').trim();
                final label = TitleGenerator.getIdeaName(thought);

                return Tooltip(
                  message: content.length > 100
                      ? '${content.substring(0, 100)}...'
                      : content,
                  child: InkWell(
                    onTap: () =>
                        _showDonePeekSheet(context, provider, thought, colors),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colors.done.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 32,
                            color: colors.done,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            label.isNotEmpty ? label : 'Done note',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: appFont(
                              color: colors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Pagination: "Show more files" (+9 at a time)
            if (filteredDone.length > visibleCount) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () {
                    setState(() => _visibleDoneCount += 9);
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.gold, width: 1.2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Show more files (${filteredDone.length - visibleCount} remaining)',
                    style: appFont(
                      color: colors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // --- Done Peek Sheet (Section 5 & Section D: Exact buttons in order) ---
  void _showDonePeekSheet(
    BuildContext context,
    ThoughtProvider provider,
    Map<String, dynamic> thought,
    AppColors colors,
  ) {
    final thoughtId = thought['thought_id'] as String? ?? 'LOG';
    final ideaName = TitleGenerator.getIdeaName(thought);
    final timestamp = IdeaFormatters.formatReadableTimestamp(thought['created_at'] as int?);
    final captureIcon = IdeaFormatters.getCaptureIcon(thought['audio_path'] ?? thought['type']);
    final bucket = thought['bucket'] as String? ?? 'Unsorted';
    final content = thought['content'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final settings = ctx.read<SettingsService>();
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: colors.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: Name + Bucket + Small LOG id
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, size: 18, color: colors.done),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ideaName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: appFont(
                                  color: colors.gold,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (captureIcon != null) ...[
                              Icon(captureIcon, size: 12, color: colors.mute),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              timestamp,
                              style: appFont(color: colors.mute, fontSize: 11),
                            ),
                            const SizedBox(width: 6),
                            Text('•', style: appFont(color: colors.mute, fontSize: 11)),
                            const SizedBox(width: 6),
                            Text(
                              thoughtId,
                              style: appFont(
                                color: colors.mute.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.line),
                    ),
                    child: Text(
                      bucket,
                      style: appFont(
                        color: colors.mute,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Content snippet
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    content,
                    style: appFont(
                      color: colors.text,
                      fontSize: 16,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Button List in Exact Order (Section D):
              // 1. Open full idea
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => IdeaDetailScreen(thought: thought),
                      ),
                    );
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open full idea'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 2. Edit
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showEditIdeaDialog(context, provider, thought, colors);
                  },
                  icon: Icon(Icons.edit_outlined,
                      size: 18, color: colors.text),
                  label: Text('Edit',
                      style: appFont(
                          color: colors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 3. Copy
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Clipboard.setData(ClipboardData(text: content));
                    _showUndoSnackBar(
                        'Copied "$ideaName" to clipboard', () {});
                  },
                  icon: Icon(Icons.copy_outlined,
                      size: 18, color: colors.text),
                  label: Text('Copy',
                      style: appFont(
                          color: colors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 4. Put back
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    provider.markDone(thought['id'], false);
                    SoundService.instance.play(SoundEvent.drop, settings: settings);
                    _showUndoSnackBar(
                        'Put "$ideaName" back to active', () {
                      provider.markDone(thought['id'], true);
                    });
                  },
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Put back'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.done,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 5. Trash
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    provider.moveToTrash(thought['id']);
                    SoundService.instance.play(SoundEvent.trash, settings: settings);
                    _showUndoSnackBar('Moved "$ideaName" to trash', () {
                      provider.restoreFromTrash(thought['id']);
                    });
                  },
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: colors.bad),
                  label: Text(
                    'Trash',
                    style:
                        appFont(color: colors.bad, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.bad.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // 6. Close
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: Icon(Icons.close, size: 18, color: colors.mute),
                  label: Text(
                    'Close',
                    style: appFont(color: colors.mute, fontSize: 14),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================================
  // VIEW: TRASH SCREEN (Section 6: 12 at a time + 2-step delete forever)
  // ==========================================================================
  Widget _buildTrashScreen(
    ThoughtProvider provider,
    NavigationNotifier nav,
    AppColors colors,
    SettingsService settings,
  ) {
    final trashedList = provider.trashedThoughts;

    if (trashedList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, size: 64, color: colors.mute),
              const SizedBox(height: 16),
              Text(
                'Trash is empty',
                style: appFont(
                  color: colors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Deleted ideas appear here. You can restore them or permanently delete them.',
                textAlign: TextAlign.center,
                style: appFont(color: colors.mute, fontSize: 16, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    final visibleCount = math.min(_visibleTrashCount, trashedList.length);
    final visibleTrash = trashedList.take(visibleCount).toList();

    return ListView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      children: [
        // Header with count
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Trash (${trashedList.length})',
              style: appFont(
                color: colors.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Stored locally',
              style: appFont(color: colors.mute, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),

        ...visibleTrash.map((thought) {
          final thoughtId = thought['thought_id'] as String? ?? 'LOG';
          final ideaName = TitleGenerator.getIdeaName(thought);
          final timestamp = IdeaFormatters.formatReadableTimestamp(thought['created_at'] as int?);
          final captureIcon = IdeaFormatters.getCaptureIcon(thought['audio_path'] ?? thought['type']);
          final bool isConfirming = (_deletingForeverId == thought['id']);

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ideaName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appFont(
                        color: colors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (captureIcon != null) ...[
                          Icon(captureIcon, size: 12, color: colors.mute),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          timestamp,
                          style: appFont(color: colors.mute, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CappedText(
                  text: thought['content'] as String? ?? '',
                  colors: colors,
                  fontSize: 15,
                ),
                const SizedBox(height: 14),
                // Button list in exact order (Section D):
                // 1. Restore  2. Edit
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            provider.restoreFromTrash(thought['id']);
                            SoundService.instance.play(SoundEvent.drop, settings: settings);
                            _showUndoSnackBar('Restored "$ideaName"', () {
                              provider.moveToTrash(thought['id']);
                            });
                          },
                          icon: const Icon(Icons.restore, size: 18),
                          label: const Text('Restore'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.gold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _showEditIdeaDialog(
                                context, provider, thought, colors);
                          },
                          icon: Icon(Icons.edit_outlined,
                              size: 18, color: colors.text),
                          label: Text(
                            'Edit',
                            style: appFont(
                              color: colors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 3. Copy  4. Delete forever (second tap confirms)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(
                                text: thought['content'] as String? ?? ''));
                            _showUndoSnackBar(
                                'Copied "$ideaName" to clipboard', () {});
                          },
                          icon: Icon(Icons.copy_outlined,
                              size: 18, color: colors.text),
                          label: Text(
                            'Copy',
                            style: appFont(
                              color: colors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: colors.line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (isConfirming) {
                              provider.deleteForever(thought['id']);
                              SoundService.instance.play(SoundEvent.deleteForever, settings: settings);
                              setState(() => _deletingForeverId = null);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Permanently deleted $thoughtId'),
                                  duration: const Duration(seconds: 3),
                                  backgroundColor: colors.card,
                                ),
                              );
                            } else {
                              SoundService.instance.play(SoundEvent.tap, settings: settings);
                              setState(() => _deletingForeverId = thought['id']);
                            }
                          },
                          icon: Icon(
                            Icons.delete_forever,
                            size: 18,
                            color: isConfirming ? Colors.white : colors.bad,
                          ),
                          label: Text(
                            isConfirming
                                ? 'Tap again to delete'
                                : 'Delete forever',
                            style: appFont(
                              color: isConfirming ? Colors.white : colors.bad,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor:
                                isConfirming ? colors.bad : Colors.transparent,
                            side: BorderSide(
                                color: isConfirming ? colors.bad : colors.line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),

        // Pagination: Show more
        if (trashedList.length > visibleCount) ...[
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () {
                setState(() => _visibleTrashCount += 12);
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.gold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Show more (${trashedList.length - visibleCount} remaining)',
                style: appFont(color: colors.gold, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================================================
  // DIALOGS & CONTEXT MENUS
  // ==========================================================================

  // --- Create / Edit Bucket Dialog with 12 Icon Selector Grid ---
  // ignore: unused_element
  void _showCreateBucketDialog(
    BuildContext context,
    ThoughtProvider provider,
    AppColors colors, {
    String? fileThoughtId,
  }) {
    final nameController = TextEditingController();
    String selectedIcon = 'folder';

    setState(() => _isModalOpen = true);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return KeyboardSafeSheet(
            isDialog: true,
            backgroundColor: colors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.gold, width: 1.5),
            header: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'New bucket',
                style: appFont(
                  color: colors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            pinnedFooter: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Cancel', style: appFont(color: colors.mute)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isNotEmpty) {
                        final settings = context.read<SettingsService>();
                        Navigator.pop(ctx);
                        await provider.addBucket(name, icon: selectedIcon);
                        SoundService.instance.play(SoundEvent.save, settings: settings);
                        if (fileThoughtId != null) {
                          await provider.fileThought(fileThoughtId, name);
                          _showUndoSnackBar('Filed to $name', () {
                            provider.unfileThought(fileThoughtId);
                          });
                          setState(() {});
                        } else {
                          _showUndoSnackBar('Created bucket "$name"', () {});
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.gold,
                      foregroundColor: Colors.black,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Save',
                      style: appFont(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: appFont(color: colors.text, fontSize: 16),
                    decoration: InputDecoration(
                      labelText: 'Bucket name',
                      labelStyle: appFont(color: colors.mute),
                      filled: true,
                      fillColor: colors.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colors.gold, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Choose an icon',
                    style: appFont(
                      color: colors.mute,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 12 Icons Selector Grid (Section 2)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kBucketIcons.entries.map((entry) {
                      final isSelected = selectedIcon == entry.key;
                      return GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedIcon = entry.key),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isSelected ? colors.goldBg : colors.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? colors.gold : colors.line,
                              width: isSelected ? 2.0 : 1.0,
                            ),
                          ),
                          child: Icon(
                            entry.value,
                            size: 22,
                            color: isSelected ? colors.gold : colors.mute,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  // --- Bucket Context Menu (Rename, Change icon, Delete) ---
  void _showBucketContextMenu(
    BuildContext context,
    ThoughtProvider provider,
    String bucketName,
    String currentIcon,
    int ideaCount,
    AppColors colors,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: colors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bucketName,
              style: appFont(
                color: colors.gold,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '$ideaCount ideas',
              style: appFont(color: colors.mute, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.edit_outlined, color: colors.text),
              title: Text('Rename bucket', style: appFont(color: colors.text)),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameBucketDialog(context, provider, bucketName, colors);
              },
            ),
            ListTile(
              leading: Icon(Icons.image_outlined, color: colors.text),
              title: Text('Change icon', style: appFont(color: colors.text)),
              onTap: () {
                Navigator.pop(ctx);
                _showChangeIconDialog(
                    context, provider, bucketName, currentIcon, colors);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: colors.bad),
              title: Text('Delete bucket',
                  style: appFont(color: colors.bad, fontWeight: FontWeight.bold)),
              subtitle: Text(
                'Moves all $ideaCount ideas back to Unsorted',
                style: appFont(color: colors.mute, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteBucketDialog(
                    context, provider, bucketName, ideaCount, colors);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameBucketDialog(
    BuildContext context,
    ThoughtProvider provider,
    String oldName,
    AppColors colors,
  ) {
    final controller = TextEditingController(text: oldName);
    setState(() => _isModalOpen = true);
    showDialog(
      context: context,
      builder: (ctx) => KeyboardSafeSheet(
        isDialog: true,
        backgroundColor: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.line),
        header: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Rename bucket',
            style: appFont(color: colors.text, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        pinnedFooter: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: appFont(color: colors.mute)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  final newName = controller.text.trim();
                  if (newName.isNotEmpty && newName != oldName) {
                    final settings = context.read<SettingsService>();
                    Navigator.pop(ctx);
                    await provider.renameBucket(oldName, newName);
                    SoundService.instance.play(SoundEvent.save, settings: settings);
                    _showUndoSnackBar('Renamed bucket to "$newName"', () {});
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: colors.gold),
                child: Text('Save',
                    style: appFont(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        child: TextField(
          controller: controller,
          autofocus: true,
          style: appFont(color: colors.text),
          decoration: InputDecoration(
            labelText: 'Bucket name',
            labelStyle: appFont(color: colors.mute),
            filled: true,
            fillColor: colors.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  void _showChangeIconDialog(
    BuildContext context,
    ThoughtProvider provider,
    String bucketName,
    String currentIcon,
    AppColors colors,
  ) {
    String selected = currentIcon;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: colors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Change bucket icon',
                style: appFont(color: colors.text, fontWeight: FontWeight.bold)),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kBucketIcons.entries.map((entry) {
                final isSelected = selected == entry.key;
                return GestureDetector(
                  onTap: () => setDialogState(() => selected = entry.key),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected ? colors.goldBg : colors.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? colors.gold : colors.line,
                        width: isSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: Icon(
                      entry.value,
                      size: 22,
                      color: isSelected ? colors.gold : colors.mute,
                    ),
                  ),
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: appFont(color: colors.mute)),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await provider.updateBucketIcon(bucketName, selected);
                  _showUndoSnackBar('Updated icon for "$bucketName"', () {});
                },
                style: ElevatedButton.styleFrom(backgroundColor: colors.gold),
                child: Text('Save',
                    style: appFont(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDeleteBucketDialog(
    BuildContext context,
    ThoughtProvider provider,
    String bucketName,
    int ideaCount,
    AppColors colors,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete "$bucketName"?',
            style: appFont(color: colors.bad, fontWeight: FontWeight.bold)),
        content: Text(
          'This will move all $ideaCount ideas back to Unsorted. Ideas will not be deleted.',
          style: appFont(color: colors.text, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: appFont(color: colors.mute)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.deleteBucket(bucketName);
              _showUndoSnackBar('Deleted bucket "$bucketName"', () {});
            },
            style: ElevatedButton.styleFrom(backgroundColor: colors.bad),
            child: Text('Delete bucket',
                style: appFont(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSplitIdeaDialog(
    BuildContext context,
    ThoughtProvider provider,
    Map<String, dynamic> idea,
    AppColors colors,
  ) {
    final title = (idea['title'] as String?)?.isNotEmpty == true
        ? idea['title'] as String
        : (idea['content'] as String? ?? '');
    final content = idea['content'] as String? ?? '';
    final bucket = (idea['bucket'] as String?)?.trim() ?? 'General';
    final initialText = content.trim().isNotEmpty ? content.trim() : title.trim();
    final ctrl = TextEditingController(text: initialText);
    bool keepOriginal = true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.line),
        ),
        title: Row(
          children: [
            Icon(Icons.splitscreen, color: colors.gold, size: 22),
            const SizedBox(width: 8),
            Text(
              'Split into Smaller Tasks',
              style: appFont(
                color: colors.text,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Original: "$title"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: appFont(color: colors.mute, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                'Enter each new task on a separate line:',
                style: appFont(
                  color: colors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 5,
                autofocus: true,
                style: appFont(color: colors.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Task 1\nTask 2\nTask 3',
                  hintStyle: appFont(color: colors.mute.withValues(alpha: 0.5)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: colors.gold),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              StatefulBuilder(
                builder: (context, setDialogState) {
                  return Container(
                    decoration: BoxDecoration(
                      color: colors.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.line),
                    ),
                    child: CheckboxListTile(
                      value: keepOriginal,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      activeColor: colors.gold,
                      checkColor: Colors.black,
                      title: Text(
                        'Keep original note in "$bucket"',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        keepOriginal
                            ? 'Original note remains safely in bucket'
                            : 'Original note will be moved to Trash once split',
                        style: appFont(color: colors.mute, fontSize: 11),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          keepOriginal = val ?? true;
                        });
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: appFont(color: colors.mute)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.gold,
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              final lines = ctrl.text
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList();
              if (lines.isEmpty) return;

              Navigator.pop(ctx);
              final result = await provider.splitThought(idea['id'], lines,
                  keepOriginal: keepOriginal);

              if (context.mounted) {
                final originalMsg = keepOriginal
                    ? 'Original note kept in "$bucket".'
                    : 'Original note moved to Trash.';
                final fullMsg = result.pinnedCount < result.createdCount
                    ? 'Created ${result.createdCount} tasks in "$bucket". Pinned ${result.pinnedCount}; remaining tasks kept in bucket (board full 8/8). $originalMsg'
                    : 'Created and pinned ${result.createdCount} tasks in "$bucket". $originalMsg';

                _showUndoSnackBar(
                  fullMsg,
                  !keepOriginal
                      ? () async {
                          await provider.restoreFromTrash(idea['id']);
                          await provider.loadThoughts();
                        }
                      : () {},
                );
              }
            },
            child: const Text('Split Task'),
          ),
        ],
      ),
    );
  }

  // --- Idea Context Menu (Step 2: Shared ⋯ Menu with large 52px buttons) ---
  void _showIdeaContextMenu(
    BuildContext context,
    ThoughtProvider provider,
    Map<String, dynamic> idea,
    AppColors colors,
  ) {
    final nav = context.read<NavigationNotifier>();
    final settings = context.read<SettingsService>();
    final ideaName = TitleGenerator.getIdeaName(idea);
    final timestamp = IdeaFormatters.formatReadableTimestamp(idea['created_at'] as int?);
    final captureIcon = IdeaFormatters.getCaptureIcon(idea['audio_path'] ?? idea['type']);
    final content = idea['content'] as String? ?? '';
    final whenVal = idea['when_val'] as String? ?? 'Soon';
    final timeVal = idea['time_val'] as String? ?? 'Medium';

    Widget buildMenuItem({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      Color? iconColor,
      Color? textColor,
      Widget? trailing,
    }) {
      return SizedBox(
        height: 52,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(icon, color: iconColor ?? colors.text, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: appFont(
                      color: textColor ?? colors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: colors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ideaName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      color: colors.gold,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (captureIcon != null) ...[
                        Icon(captureIcon, size: 12, color: colors.mute),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        timestamp,
                        style: appFont(color: colors.mute, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 12),

            // 1. Mark done / Mark active
            buildMenuItem(
              icon: idea['done'] == 1 ? Icons.undo : Icons.check_circle_outline,
              iconColor: colors.gold,
              textColor: colors.gold,
              label: idea['done'] == 1 ? 'Mark as active' : 'Mark done',
              onTap: () async {
                Navigator.pop(ctx);
                final markDone = idea['done'] != 1;
                await provider.markDone(idea['id'], markDone);
                SoundService.instance.play(SoundEvent.save, settings: settings);
                _showUndoSnackBar(
                  markDone ? 'Marked "$ideaName" as done' : 'Marked "$ideaName" as active',
                  () {
                    provider.markDone(idea['id'], !markDone);
                  },
                );
              },
            ),

            // 2. Split into smaller tasks (Requirement 4)
            buildMenuItem(
              icon: Icons.splitscreen,
              iconColor: colors.gold,
              textColor: colors.gold,
              label: 'Split into smaller tasks',
              onTap: () {
                Navigator.pop(ctx);
                _showSplitIdeaDialog(context, provider, idea, colors);
              },
            ),

            // 3. Pin to board / Remove from board (Requirement 5 & 6)
            Builder(
              builder: (context) {
                final isPinned = provider.isPinned(idea);
                final isBoardFull = provider.isBoardFull;

                if (isPinned) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      buildMenuItem(
                        icon: Icons.open_in_full,
                        iconColor: colors.gold,
                        textColor: colors.gold,
                        label: 'View on board',
                        onTap: () {
                          Navigator.pop(ctx);
                          nav.setBoardExpanded(true);
                        },
                      ),
                      buildMenuItem(
                        icon: Icons.push_pin,
                        iconColor: colors.gold,
                        textColor: colors.gold,
                        label: 'Remove from board',
                        onTap: () async {
                          Navigator.pop(ctx);
                          await provider.unpinFromBoard(idea['id']);
                          _showUndoSnackBar('Removed "$ideaName" from board', () {
                            provider.pinToBoard(idea['id']);
                          });
                        },
                      ),
                    ],
                  );
                } else if (isBoardFull) {
                  return buildMenuItem(
                    icon: Icons.push_pin_outlined,
                    iconColor: colors.mute,
                    textColor: colors.mute,
                    label: 'Pin to board',
                    trailing: Text(
                      'Board full (8/8)',
                      style: appFont(color: colors.mute, fontSize: 11),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showUndoSnackBar(
                        'Board is full (8/8). Remove a note from the board first.',
                        () {},
                      );
                    },
                  );
                } else {
                  return buildMenuItem(
                    icon: Icons.push_pin_outlined,
                    iconColor: colors.gold,
                    label: 'Pin to board',
                    onTap: () async {
                      Navigator.pop(ctx);
                      final ok = await provider.pinToBoard(idea['id']);
                      if (ok) {
                        _showUndoSnackBar('Pinned "$ideaName" to board', () {
                          provider.unpinFromBoard(idea['id']);
                        });
                      } else {
                        _showUndoSnackBar(
                          'Board is full (8/8). Remove a note from the board first.',
                          () {},
                        );
                      }
                    },
                  );
                }
              },
            ),

            // 1. Edit
            buildMenuItem(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onTap: () {
                Navigator.pop(ctx);
                _showEditIdeaDialog(context, provider, idea, colors);
              },
            ),

            // 2. Copy
            buildMenuItem(
              icon: Icons.copy_outlined,
              label: 'Copy',
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: content));
                _showUndoSnackBar('Copied "$ideaName" to clipboard', () {});
              },
            ),

            // 3. "When: Soon" (opens small chooser: Today, Soon, Later)
            buildMenuItem(
              icon: Icons.schedule_outlined,
              label: 'When: $whenVal',
              trailing: Icon(Icons.chevron_right, color: colors.mute, size: 20),
              onTap: () {
                Navigator.pop(ctx);
                _showWhenChooser(context, provider, idea, colors, settings);
              },
            ),

            // 4. "Time: Medium" (opens small chooser: Quick, Medium, Long)
            buildMenuItem(
              icon: Icons.timer_outlined,
              label: 'Time: $timeVal',
              trailing: Icon(Icons.chevron_right, color: colors.mute, size: 20),
              onTap: () {
                Navigator.pop(ctx);
                _showTimeChooser(context, provider, idea, colors, settings);
              },
            ),

            // 5. Move to another bucket (opens the existing "Choose a bucket" popup, which can create buckets)
            buildMenuItem(
              icon: Icons.drive_file_move_outlined,
              label: 'Move to another bucket',
              onTap: () {
                Navigator.pop(ctx);
                _showChooseBucketPopup(
                  context: context,
                  provider: provider,
                  idea: idea,
                  colors: colors,
                  heading: 'Move to another bucket',
                );
              },
            ),

            // 6. Move back to Unsorted
            buildMenuItem(
              icon: Icons.inbox_outlined,
              label: 'Move back to Unsorted',
              onTap: () {
                final oldBucket = idea['bucket'] as String?;
                Navigator.pop(ctx);
                provider.unfileThought(idea['id']);
                SoundService.instance.play(SoundEvent.drop, settings: settings);
                _showUndoSnackBar('Moved "$ideaName" back to Unsorted', () {
                  if (oldBucket != null && oldBucket.isNotEmpty) {
                    provider.fileThought(idea['id'], oldBucket);
                  }
                });
              },
            ),

            // 7. Move to Trash
            buildMenuItem(
              icon: Icons.delete_outline,
              label: 'Move to Trash',
              iconColor: colors.bad,
              textColor: colors.bad,
              onTap: () {
                Navigator.pop(ctx);
                provider.moveToTrash(idea['id']);
                SoundService.instance.play(SoundEvent.trash, settings: settings);
                _showUndoSnackBar('Moved to Trash', () {
                  provider.restoreFromTrash(idea['id']);
                });
              },
            ),

            const Divider(height: 12),

            // 8. Cancel
            buildMenuItem(
              icon: Icons.close,
              label: 'Cancel',
              iconColor: colors.mute,
              textColor: colors.mute,
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  // --- Small Chooser for When (Today, Soon, Later) ---
  void _showWhenChooser(
    BuildContext context,
    ThoughtProvider provider,
    Map<String, dynamic> idea,
    AppColors colors,
    SettingsService settings,
  ) {
    final currentWhen = idea['when_val'] as String? ?? 'Soon';
    final options = ['Today', 'Soon', 'Later'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: colors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Text(
                'When is this due?',
                style: appFont(
                  color: colors.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final opt in options)
              SizedBox(
                height: 52,
                child: InkWell(
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (opt == currentWhen) return;
                    await DatabaseHelper.instance
                        .updateThoughtRanking(idea['id'], whenVal: opt);
                    await provider.loadThoughts();
                    _showUndoSnackBar('When set to $opt', () async {
                      await DatabaseHelper.instance.updateThoughtRanking(
                          idea['id'],
                          whenVal: currentWhen);
                      await provider.loadThoughts();
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          opt,
                          style: appFont(
                            color:
                                opt == currentWhen ? colors.gold : colors.text,
                            fontSize: 16,
                            fontWeight: opt == currentWhen
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                        if (opt == currentWhen)
                          Icon(Icons.check, color: colors.gold, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // --- Small Chooser for Time (Quick, Medium, Long) ---
  void _showTimeChooser(
    BuildContext context,
    ThoughtProvider provider,
    Map<String, dynamic> idea,
    AppColors colors,
    SettingsService settings,
  ) {
    final currentTime = idea['time_val'] as String? ?? 'Medium';
    final options = ['Quick', 'Medium', 'Long'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: colors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 12),
              child: Text(
                'How much time does it take?',
                style: appFont(
                  color: colors.gold,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            for (final opt in options)
              SizedBox(
                height: 52,
                child: InkWell(
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (opt == currentTime) return;
                    await DatabaseHelper.instance
                        .updateThoughtRanking(idea['id'], timeVal: opt);
                    await provider.loadThoughts();
                    _showUndoSnackBar('Time set to $opt', () async {
                      await DatabaseHelper.instance.updateThoughtRanking(
                          idea['id'],
                          timeVal: currentTime);
                      await provider.loadThoughts();
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          opt,
                          style: appFont(
                            color:
                                opt == currentTime ? colors.gold : colors.text,
                            fontSize: 16,
                            fontWeight: opt == currentTime
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                        if (opt == currentTime)
                          Icon(Icons.check, color: colors.gold, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // --- Shared Bucket Popup (Section B: Reused for every move) ---
  void _showChooseBucketPopup({
    required BuildContext context,
    required ThoughtProvider provider,
    required Map<String, dynamic> idea,
    required AppColors colors,
    String heading = 'Choose a bucket',
  }) {
    final currentBucket = (idea['bucket'] as String?)?.trim();
    final ideaName = TitleGenerator.getIdeaName(idea);
    final searchController = TextEditingController();
    String query = '';
    bool isAdding = false;
    String? errorMessage;

    setState(() => _isModalOpen = true);
    KeyboardSafeSheet.show(
      context: context,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setPopupState) {
            // Destination list excludes the current bucket (Section B)
            final availableBuckets = provider.buckets.where((b) {
              final name = (b['name'] as String).trim();
              if (currentBucket != null && currentBucket.isNotEmpty) {
                if (name.toLowerCase() == currentBucket.toLowerCase()) {
                  return false;
                }
              }
              return true;
            }).toList();

            // UPDATE 6 - Section C: Show most used 3 buckets first, then the rest alphabetically
            final sortedByUsage = List<Map<String, dynamic>>.from(availableBuckets);
            sortedByUsage.sort((a, b) {
              final countA = provider.getIdeaCountForBucket(a['name'] as String);
              final countB = provider.getIdeaCountForBucket(b['name'] as String);
              if (countB != countA) {
                return countB.compareTo(countA); // most ideas first
              }
              return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
            });

            final top3 = sortedByUsage.take(3).toList();
            final rest = sortedByUsage.skip(3).toList();
            rest.sort((a, b) =>
                (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

            final orderedBuckets = [...top3, ...rest];

            final filteredBuckets = orderedBuckets.where((b) {
              if (query.isEmpty) return true;
              final name = (b['name'] as String).toLowerCase();
              return name.contains(query.toLowerCase());
            }).toList();

            final trimmedQuery = query.trim();
            final bool isCurrentBucketName = currentBucket != null &&
                currentBucket.toLowerCase() == trimmedQuery.toLowerCase();
            final bool exactMatchInAll = provider.buckets.any((b) =>
                (b['name'] as String).trim().toLowerCase() ==
                trimmedQuery.toLowerCase());
            final bool showCreateRow = trimmedQuery.isNotEmpty &&
                !isCurrentBucketName &&
                !exactMatchInAll;

            Future<void> onSelectBucket(String targetBucket) async {
              setPopupState(() {
                isAdding = true;
                errorMessage = null;
              });

              final s = context.read<SettingsService>();
              try {
                // One-step save: create if needed (never creating a duplicate), move idea, save, then close.
                final canonicalName = await provider.addBucket(targetBucket);
                final destination =
                    canonicalName.isNotEmpty ? canonicalName : targetBucket;

                final oldBucket = idea['bucket'] as String?;
                await provider.fileThought(idea['id'], destination);

                final remainingUnsorted = provider.unsortedThoughts.length;
                if (remainingUnsorted == 0) {
                  SoundService.instance.play(SoundEvent.celebrate, settings: s);
                } else {
                  SoundService.instance.play(SoundEvent.drop, settings: s);
                }

                if (modalCtx.mounted && Navigator.canPop(modalCtx)) {
                  Navigator.pop(modalCtx);
                }

                if (mounted) {
                  _showUndoSnackBar('Filed "$ideaName" in $destination', () {
                    if (oldBucket != null && oldBucket.isNotEmpty) {
                      provider.fileThought(idea['id'], oldBucket);
                    } else {
                      provider.unfileThought(idea['id']);
                    }
                  });

                  if (idea['bucket'] == null ||
                      (idea['bucket'] as String).trim().isEmpty) {
                    setState(() {});
                  }
                }
              } catch (e) {
                SoundService.instance.play(SoundEvent.error, settings: s);
                setPopupState(() {
                  isAdding = false;
                  errorMessage =
                      'Could not move idea to bucket. Please try again.';
                });
              }
            }

            return KeyboardSafeSheet(
              openingHeight: 474.0,
              backgroundColor: colors.bg,
              header: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              heading,
                              style: appFont(
                                color: colors.gold,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Adding "${KeyboardSafeSheet.formatIdeaHeading(idea)}" to…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: appFont(
                                color: colors.mute,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: colors.mute, size: 20),
                        onPressed: () => Navigator.pop(modalCtx),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              pinnedHeader: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // "Find or create a bucket" Field
                  Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.line),
                    ),
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      onChanged: (val) {
                        setPopupState(() {
                          query = val;
                          errorMessage = null;
                        });
                      },
                      style: appFont(color: colors.text, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: 'Find or create a bucket...',
                        hintStyle: appFont(color: colors.mute, fontSize: 14),
                        prefixIcon:
                            Icon(Icons.search, color: colors.mute, size: 20),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close,
                                    color: colors.mute, size: 18),
                                onPressed: () {
                                  searchController.clear();
                                  setPopupState(() {
                                    query = '';
                                    errorMessage = null;
                                  });
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),

                  // The Create row sits directly under search field, always visible above keyboard (>= 56px)
                  if (showCreateRow) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: colors.gold.withValues(alpha: 0.6)),
                      ),
                      child: InkWell(
                        onTap: isAdding
                            ? null
                            : () => onSelectBucket(trimmedQuery),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Icon(Icons.add_circle,
                                  color: colors.gold, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Create "$trimmedQuery"',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: appFont(
                                    color: colors.gold,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage!,
                      style: appFont(color: colors.bad, fontSize: 13),
                    ),
                  ],

                  if (isAdding) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.gold,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Adding…',
                          style: appFont(
                            color: colors.gold,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),
                ],
              ),
              child: ListView(
                children: [
                  if (filteredBuckets.isEmpty && !showCreateRow)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          query.isEmpty
                              ? 'No other buckets available'
                              : 'No buckets matching "$query"',
                          style:
                              appFont(color: colors.mute, fontSize: 14),
                        ),
                      ),
                    ),

                  ...filteredBuckets.map((b) {
                    final name = b['name'] as String;
                    final iconKey = (b['icon'] as String?) ?? 'folder';
                    final iconData =
                        kBucketIcons[iconKey] ?? Icons.folder_outlined;
                    final count = provider.getIdeaCountForBucket(name);

                    return Container(
                      height: 56,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: colors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.line),
                      ),
                      child: InkWell(
                        onTap: isAdding
                            ? null
                            : () => onSelectBucket(name),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14),
                          child: Row(
                            children: [
                              Icon(iconData,
                                  color: colors.gold, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: appFont(
                                    color: colors.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '$count ${count == 1 ? 'idea' : 'ideas'}',
                                style: appFont(
                                    color: colors.mute, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }

  // --- Read More Full Detail Popup (Section 1: Fixed-Size Card Popup) ---
  void _showReadMorePopup({
    required BuildContext context,
    required Map<String, dynamic> idea,
    required ThoughtProvider provider,
    required AppColors colors,
    required SettingsService settings,
  }) {
    final isDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
        MediaQuery.of(context).size.width >= 600;

    final name = TitleGenerator.getIdeaName(idea);
    final timestamp =
        IdeaFormatters.formatReadableTimestamp(idea['created_at'] as int?);
    final captureIcon =
        IdeaFormatters.getCaptureIcon(idea['audio_path'] ?? idea['type']);
    final bucket = (idea['bucket'] as String?)?.trim() ?? 'Unsorted';
    final thoughtId = idea['thought_id'] as String? ?? 'LOG';
    final content = idea['content'] as String? ?? '';
    final whenVal = idea['when_val'] as String? ?? 'Soon';
    final timeVal = idea['time_val'] as String? ?? 'Medium';

    Widget buildPopupContent(BuildContext ctx) {
      return Container(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Name + Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: appFont(
                      color: colors.gold,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: colors.mute, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Subtitle row: timestamp, capture icon, bucket, small LOG id, When & Time
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                if (captureIcon != null)
                  Icon(captureIcon, size: 14, color: colors.mute),
                Text(
                  timestamp,
                  style: appFont(color: colors.mute, fontSize: 12),
                ),
                Text('•', style: appFont(color: colors.mute, fontSize: 12)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.line),
                  ),
                  child: Text(
                    bucket.isNotEmpty ? bucket : 'Unsorted',
                    style: appFont(
                      color: colors.mute,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text('•', style: appFont(color: colors.mute, fontSize: 12)),
                Text(
                  thoughtId,
                  style: appFont(
                    color: colors.mute.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
                Text('•', style: appFont(color: colors.mute, fontSize: 12)),
                Text(
                  'When: $whenVal · Time: $timeVal',
                  style: appFont(
                    color: colors.mute,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Full text (scrollable)
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 320),
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.line),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    content.isNotEmpty ? content : '(empty idea)',
                    style:
                        appFont(color: colors.text, fontSize: 15, height: 1.45),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Buttons: Edit, Copy, Close (each min 48px height)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showEditIdeaDialog(context, provider, idea, colors);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: content));
                        _showUndoSnackBar('Copied "$name" to clipboard', () {});
                      },
                      icon: Icon(Icons.copy_outlined,
                          size: 18, color: colors.text),
                      label: Text('Copy',
                          style: appFont(color: colors.text)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: colors.line),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Close',
                        style: appFont(color: colors.mute, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (isDesktop) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: colors.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: colors.line),
          ),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
            child: buildPopupContent(ctx),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: colors.line),
          ),
          child: buildPopupContent(ctx),
        ),
      );
    }
  }

  // --- Edit Idea Dialog (Name field, Groq suggestion button, preservation) ---
  void _showEditIdeaDialog(
    BuildContext context,
    ThoughtProvider provider,
    Map<String, dynamic> idea,
    AppColors colors,
  ) {
    final thoughtId = idea['thought_id'] as String? ?? 'LOG';
    final currentContent = idea['content'] as String? ?? '';
    final currentTitle = TitleGenerator.getIdeaName(idea);
    final bucket = idea['bucket'] as String? ?? 'Unsorted';
    final whenVal = idea['when_val'] as String? ?? 'Soon';
    final timeVal = idea['time_val'] as String? ?? 'Medium';

    final titleController = TextEditingController(text: currentTitle);
    final contentController = TextEditingController(text: currentContent);
    bool isSuggesting = false;
    String? suggestionStatus;

    setState(() => _isModalOpen = true);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => KeyboardSafeSheet(
          isDialog: true,
          maxWidth: 540,
          backgroundColor: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.gold, width: 1.5),
          header: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.edit_note, color: colors.gold, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Edit Idea',
                    style: appFont(
                      color: colors.text,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  thoughtId,
                  style: appFont(
                    color: colors.mute,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          pinnedFooter: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  height: 48,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Icon(Icons.close, color: colors.mute, size: 18),
                    label: Text('Cancel', style: appFont(color: colors.mute)),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final newContent = contentController.text.trim();
                      final newTitle = titleController.text.trim();
                      if (newContent.isNotEmpty) {
                        final s = context.read<SettingsService>();
                        Navigator.pop(ctx);
                        final now = DateTime.now().millisecondsSinceEpoch;
                        if (newTitle.isNotEmpty && newTitle != currentTitle) {
                          await provider.updateThoughtTitle(idea['id'], newTitle, titleSource: 'user');
                        }
                        await provider.updateContent(idea['id'], newContent, editedAt: now);
                        SoundService.instance.play(SoundEvent.save, settings: s);
                        _showUndoSnackBar('Updated "${newTitle.isNotEmpty ? newTitle : currentTitle}"', () {});
                      }
                    },
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      'Save',
                      style: appFont(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.line),
                    ),
                    child: Text(
                      'Bucket: $bucket  •  When: $whenVal  •  Time: $timeVal',
                      style: appFont(color: colors.mute, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Name field
                  Text(
                    'Name',
                    style: appFont(
                      color: colors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleController,
                    style: appFont(color: colors.text, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Idea name',
                      hintStyle: appFont(color: colors.mute),
                      filled: true,
                      fillColor: colors.bg,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colors.gold, width: 1.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Suggest a better name button using Groq
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: isSuggesting
                            ? null
                            : () async {
                                final text = contentController.text.trim();
                                if (text.isEmpty) return;
                                setDialogState(() {
                                  isSuggesting = true;
                                  suggestionStatus = null;
                                });
                                final settings = Provider.of<SettingsService>(context, listen: false);
                                final suggested = await TitleGenerator.suggestGroqName(
                                  content: text,
                                  apiKey: settings.groqApiKey,
                                );
                                setDialogState(() {
                                  isSuggesting = false;
                                  if (suggested != null && suggested.isNotEmpty) {
                                    titleController.text = suggested;
                                    suggestionStatus = 'Suggested from Groq!';
                                  } else {
                                    suggestionStatus = settings.groqApiKey.isEmpty
                                        ? 'No Groq API key set in Settings.'
                                        : 'Could not get name from Groq.';
                                  }
                                });
                              },
                        icon: isSuggesting
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.gold,
                                ),
                              )
                            : Icon(Icons.auto_awesome, size: 14, color: colors.gold),
                        label: Text(
                          'Suggest a better name',
                          style: appFont(color: colors.gold, fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.gold.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'This sends this idea’s text to Groq.',
                    style: appFont(color: colors.mute, fontSize: 11),
                  ),
                  if (suggestionStatus != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      suggestionStatus!,
                      style: appFont(
                        color: suggestionStatus!.contains('!') ? colors.gold : colors.bad,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Idea Content field
                  Text(
                    'Text',
                    style: appFont(
                      color: colors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: contentController,
                    minLines: 4,
                    maxLines: 10,
                    style: appFont(color: colors.text, fontSize: 15, height: 1.4),
                    decoration: InputDecoration(
                      hintText: 'Edit your idea...',
                      hintStyle: appFont(color: colors.mute),
                      filled: true,
                      fillColor: colors.bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: colors.gold, width: 1.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _isModalOpen = false);
    });
  }
}

// ============================================================================
// HELPER COMPONENT: CAPPED TEXT (3 lines / ~220 chars with inline Read more)
// ============================================================================
class _CappedText extends StatefulWidget {
  final String text;
  final AppColors colors;
  final double fontSize;

  const _CappedText({
    required this.text,
    required this.colors,
    this.fontSize = 16,
  });

  @override
  State<_CappedText> createState() => _CappedTextState();
}

class _CappedTextState extends State<_CappedText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final isLong = text.length > 200 || text.contains('\n\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: appFont(
            color: widget.colors.text,
            fontSize: widget.fontSize,
            height: 1.4,
          ),
        ),
        if (isLong) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(
                _expanded ? 'Show less' : 'Read more',
                style: appFont(
                  color: widget.colors.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// COMPONENT: SORTED IDEA CARD (Shared card for Sorted: Start here & buckets)
// Height: 220px desktop, 200px phone. Never changes shape.
// Header: "Start here" label (if active), bucket chip, idea name, timestamp.
// Body: 3 lines of text cut with ellipsis.
// Slot: Reserved "Read more" slot (always same height, shown only when cut).
// Reason: "Quick to finish · due soon" / RankingEngine reason line.
// Bottom: ONE row with full-width "Mark done" + 48px ⋯ button.
// ============================================================================
class SortedIdeaCard extends StatelessWidget {
  final Map<String, dynamic> idea;
  final AppColors colors;
  final ThoughtProvider provider;
  final SettingsService settings;
  final bool isStartHere;
  final bool isDesktop;
  final VoidCallback onReadMore;
  final VoidCallback onMoreOptions;
  final VoidCallback onMarkDone;

  const SortedIdeaCard({
    super.key,
    required this.idea,
    required this.colors,
    required this.provider,
    required this.settings,
    this.isStartHere = false,
    required this.isDesktop,
    required this.onReadMore,
    required this.onMoreOptions,
    required this.onMarkDone,
  });

  bool _isCut(String text, double maxWidth, TextStyle style) {
    if (text.isEmpty) return false;
    final lines = text.split('\n');
    if (lines.length > 3 || text.length > 150) return true;
    final span = TextSpan(text: text, style: style);
    final tp = TextPainter(
      text: span,
      maxLines: 3,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: maxWidth > 0 ? maxWidth : 300);
    return tp.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final ideaName = TitleGenerator.getIdeaName(idea);
    final timestamp =
        IdeaFormatters.formatReadableTimestamp(idea['created_at'] as int?);
    final captureIcon =
        IdeaFormatters.getCaptureIcon(idea['audio_path'] ?? idea['type']);
    final bucketName = (idea['bucket'] as String?)?.trim() ?? 'General';
    final iconKey = provider.getBucketIcon(bucketName);
    final iconData = kBucketIcons[iconKey] ?? Icons.folder_outlined;
    final reason = RankingEngine.getReason(idea);
    final content = idea['content'] as String? ?? '';

    final fixedHeight = isDesktop ? 220.0 : 200.0;
    final textStyle = appFont(
      color: colors.text,
      fontSize: 14,
      height: 1.3,
    );

    return SizedBox(
      height: fixedHeight,
      child: GestureDetector(
        onLongPress: onMoreOptions,
        onSecondaryTap: onMoreOptions,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isStartHere ? colors.gold : colors.line,
              width: isStartHere ? 1.8 : 1.2,
            ),
            boxShadow: isStartHere
                ? [
                    BoxShadow(
                      color: colors.gold.withValues(alpha: 0.08),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCut = _isCut(content, constraints.maxWidth, textStyle);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: "Start here" label, idea name, timestamp, and bucket chip
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (isStartHere) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colors.gold,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '★ Start here',
                                      style: appFont(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          ideaName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: appFont(
                                            color: colors.gold,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (provider.isPinned(idea)) ...[
                                        const SizedBox(width: 4),
                                        Icon(Icons.push_pin, size: 14, color: colors.gold),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (captureIcon != null) ...[
                                  Icon(captureIcon, size: 12, color: colors.mute),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  timestamp,
                                  style: appFont(color: colors.mute, fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Bucket chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.goldBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: colors.gold.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(iconData, size: 12, color: colors.gold),
                            const SizedBox(width: 4),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 100),
                              child: Text(
                                bucketName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: appFont(
                                  color: colors.gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // 3 lines of text cut with ellipsis
                  Expanded(
                    child: Text(
                      content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle,
                    ),
                  ),

                  // Reserved Read more slot (always 18px height)
                  SizedBox(
                    height: 18,
                    child: isCut
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              onTap: onReadMore,
                              borderRadius: BorderRadius.circular(4),
                              child: Text(
                                'Read more',
                                style: appFont(
                                  color: colors.gold,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 4),

                  // Plain reason line ("Quick to finish · due soon")
                  Text(
                    reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      color: colors.mute,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ONE row: full-width "Mark done" button and a 48px ⋯ button
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: ElevatedButton.icon(
                              onPressed: onMarkDone,
                              icon: const Icon(Icons.check_circle_outline,
                                  size: 18),
                              label: Text(
                                'Mark done',
                                style: appFont(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colors.done,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 48,
                          height: 40,
                          child: OutlinedButton(
                            onPressed: onMoreOptions,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.line),
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Icon(Icons.more_horiz,
                                color: colors.mute, size: 20),
                          ),
                        ),
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
  }
}

// ============================================================================
// COMPONENT: FIXED-SIZE IDEA CARD (Unsorted & Sorted bucket lists)
// Height: 220px desktop, 200px phone. Same height for short or long ideas.
// Inside: Header (name, timestamp, capture icon), 4-line text area with ellipsis,
// reserved 28px slot for "Read more" (only shown when text is cut).
// ============================================================================
class FixedIdeaCard extends StatelessWidget {
  final Map<String, dynamic> idea;
  final AppColors colors;
  final ThoughtProvider provider;
  final bool isFirst;
  final bool isDesktop;
  final VoidCallback onReadMore;
  final VoidCallback onMoreOptions;

  const FixedIdeaCard({
    super.key,
    required this.idea,
    required this.colors,
    required this.provider,
    this.isFirst = false,
    required this.isDesktop,
    required this.onReadMore,
    required this.onMoreOptions,
  });

  bool _isCut(String text, double maxWidth) {
    if (text.isEmpty) return false;
    final lines = text.split('\n');
    if (lines.length > 4 || text.length > 200) return true;
    final span = TextSpan(
      text: text,
      style: const TextStyle(fontSize: 15, height: 1.35),
    );
    final tp = TextPainter(
      text: span,
      maxLines: 4,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: maxWidth > 0 ? maxWidth : 300);
    return tp.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final name = TitleGenerator.getIdeaName(idea);
    final timestamp =
        IdeaFormatters.formatReadableTimestamp(idea['created_at'] as int?);
    final captureIcon =
        IdeaFormatters.getCaptureIcon(idea['audio_path'] ?? idea['type']);
    final content = idea['content'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFirst ? colors.gold : colors.line,
          width: isFirst ? 1.6 : 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCut = _isCut(content, constraints.maxWidth);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Name, timestamp, capture icon, ⋯ more options
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: appFont(
                                        color: colors.gold,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (provider.isPinned(idea)) ...[
                                    const SizedBox(width: 4),
                                    Icon(Icons.push_pin, size: 14, color: colors.gold),
                                  ],
                                ],
                              ),
                            ),
                            if (isFirst) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colors.gold,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '★ Start here',
                                  style: appFont(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (captureIcon != null) ...[
                              Icon(captureIcon, size: 12, color: colors.mute),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              timestamp,
                              style: appFont(
                                color: colors.mute,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_horiz, color: colors.mute, size: 20),
                    onPressed: onMoreOptions,
                    tooltip: 'More options',
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Text Area showing at most 4 lines with ellipsis
              Expanded(
                child: Text(
                  content,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(
                    color: colors.text,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),

              // Reserved slot for "Read more" that is always the same height (28px)
              SizedBox(
                height: 28,
                child: isCut
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: onReadMore,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Read more',
                              style: appFont(
                                color: colors.gold,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================================
// COMPONENT: FLOATING 3D TRASH BUTTON (Section 6 & Requirement 2)
// ============================================================================
class _Floating3DTrashButton extends StatefulWidget {
  final int trashCount;
  final bool isOpen;
  final AppColors colors;
  final VoidCallback onTap;

  const _Floating3DTrashButton({
    required this.trashCount,
    required this.isOpen,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_Floating3DTrashButton> createState() => _Floating3DTrashButtonState();
}

class _Floating3DTrashButtonState extends State<_Floating3DTrashButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    const double size = 68.0;
    final bool hasItems = widget.trashCount > 0;
    final bool isGold = widget.isOpen;

    final baseEdgeColor = isGold
        ? const Color(0xFF8A6500)
        : const Color(0xFF101012);

    final faceColor = isGold
        ? widget.colors.goldBg
        : widget.colors.card;

    final borderColor = isGold
        ? widget.colors.gold
        : widget.colors.line;

    final iconAndTextColor = isGold
        ? widget.colors.gold
        : widget.colors.text;

    return Semantics(
      button: true,
      label: 'Trash button, ${widget.trashCount} items',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: SizedBox(
          width: size,
          height: size + 6,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 3D Bottom Bevel Layer
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: size,
                child: Container(
                  decoration: BoxDecoration(
                    color: baseEdgeColor,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                ),
              ),

              // 3D Pressed/Raised Face Layer
              AnimatedPositioned(
                duration: const Duration(milliseconds: 60),
                top: _isPressed ? 4 : 0,
                left: 0,
                right: 0,
                height: size,
                child: Container(
                  decoration: BoxDecoration(
                    color: faceColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: borderColor,
                      width: isGold ? 1.8 : 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 24,
                        color: iconAndTextColor,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Trash',
                        style: appFont(
                          color: iconAndTextColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Red Count Badge
              if (hasItems)
                Positioned(
                  top: _isPressed ? 1 : -4,
                  right: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: const Color(0xFF0E0E10), width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        '${widget.trashCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// COMPONENT: BUCKET FILTER & SORT SHEET
// ============================================================================
class _BucketFilterContent extends StatefulWidget {
  final List<Map<String, dynamic>> allIdeas;
  final String searchQuery;
  final String initialDate;
  final int? initialMonth;
  final int? initialYear;
  final bool initialDateUnknown;
  final String initialSort;
  final String initialWhen;
  final String initialTime;
  final AppColors colors;
  final void Function({
    required String date,
    required int? month,
    required int? year,
    required bool dateUnknown,
    required String sort,
    required String when,
    required String time,
  }) onApply;

  const _BucketFilterContent({
    required this.allIdeas,
    required this.searchQuery,
    required this.initialDate,
    required this.initialMonth,
    required this.initialYear,
    required this.initialDateUnknown,
    required this.initialSort,
    required this.initialWhen,
    required this.initialTime,
    required this.colors,
    required this.onApply,
  });

  @override
  State<_BucketFilterContent> createState() => _BucketFilterContentState();
}

class _BucketFilterContentState extends State<_BucketFilterContent> {
  late String _date;
  late int? _month;
  late int? _year;
  late bool _dateUnknown;
  late String _sort;
  late String _when;
  late String _time;

  late final int _unknownCount;
  late final Map<int, Set<int>> _yearMonths;
  late final Map<String, int> _monthCounts;
  late final List<int> _years;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _month = widget.initialMonth;
    _year = widget.initialYear;
    _dateUnknown = widget.initialDateUnknown;
    _sort = widget.initialSort;
    _when = widget.initialWhen;
    _time = widget.initialTime;

    int unknown = 0;
    final ym = <int, Set<int>>{};
    final mc = <String, int>{};

    for (final idea in widget.allIdeas) {
      if (_StreamScreenState._isPlaceholderIdea(idea)) {
        unknown++;
      } else {
        final dt = DateTime.fromMillisecondsSinceEpoch(
                (idea['created_at'] as num).toInt())
            .toLocal();
        final y = dt.year;
        final m = dt.month;
        ym.putIfAbsent(y, () => {}).add(m);
        final key = '$y-$m';
        mc[key] = (mc[key] ?? 0) + 1;
      }
    }

    _unknownCount = unknown;
    _yearMonths = ym;
    _monthCounts = mc;
    _years = ym.keys.toList()..sort((a, b) => b.compareTo(a));

    if (_year == null && _years.isNotEmpty) {
      _year = _years.first;
    }
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colors = widget.colors;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: colors.gold,
      backgroundColor: colors.bg,
      labelStyle: appFont(
        color: isSelected ? Colors.black : colors.text,
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isSelected ? colors.gold : colors.line,
        ),
      ),
      showCheckmark: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    final matchingIdeas = _StreamScreenState._applyBucketFilters(
      allIdeas: widget.allIdeas,
      searchQuery: widget.searchQuery,
      date: _date,
      month: _month,
      year: _year,
      dateUnknown: _dateUnknown,
      sort: _sort,
      when: _when,
      time: _time,
    );
    final int matchingCount = matchingIdeas.length;

    final monthsInYear = (_year != null && _yearMonths.containsKey(_year))
        ? (_yearMonths[_year]!.toList()..sort((a, b) => b.compareTo(a)))
        : <int>[];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter & sort',
                  style: appFont(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: colors.mute, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Divider(color: colors.line, height: 1),

          // Scrollable filter options
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Date Added
                  Text(
                    'Date added',
                    style: appFont(
                      color: colors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        label: 'All time',
                        isSelected: _date == 'All time',
                        onTap: () {
                          setState(() {
                            _date = 'All time';
                            _dateUnknown = false;
                            _month = null;
                          });
                        },
                      ),
                      _buildChip(
                        label: 'This week',
                        isSelected: _date == 'This week',
                        onTap: () {
                          setState(() {
                            _date = 'This week';
                            _dateUnknown = false;
                            _month = null;
                          });
                        },
                      ),
                      _buildChip(
                        label: 'This month',
                        isSelected: _date == 'This month',
                        onTap: () {
                          setState(() {
                            _date = 'This month';
                            _dateUnknown = false;
                            _month = null;
                          });
                        },
                      ),
                      _buildChip(
                        label: 'Last month',
                        isSelected: _date == 'Last month',
                        onTap: () {
                          setState(() {
                            _date = 'Last month';
                            _dateUnknown = false;
                            _month = null;
                          });
                        },
                      ),
                      _buildChip(
                        label: 'This year',
                        isSelected: _date == 'This year',
                        onTap: () {
                          setState(() {
                            _date = 'This year';
                            _dateUnknown = false;
                            _month = null;
                          });
                        },
                      ),
                      _buildChip(
                        label: 'Pick a month',
                        isSelected: _date == 'Pick a month',
                        onTap: () {
                          setState(() {
                            _date = 'Pick a month';
                            if (_year == null && _years.isNotEmpty) {
                              _year = _years.first;
                            }
                            if (_month == null &&
                                _year != null &&
                                _yearMonths.containsKey(_year) &&
                                _yearMonths[_year]!.isNotEmpty) {
                              _month = _yearMonths[_year]!.reduce(math.max);
                            }
                          });
                        },
                      ),
                    ],
                  ),

                  // "Pick a month" sub-selector
                  if (_date == 'Pick a month') ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_years.isNotEmpty) ...[
                            Text(
                              'Year:',
                              style: appFont(
                                color: colors.mute,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _years.map((y) {
                                return _buildChip(
                                  label: '$y',
                                  isSelected: (_year == y),
                                  onTap: () {
                                    setState(() {
                                      _year = y;
                                      _dateUnknown = false;
                                      final ym = _yearMonths[y];
                                      if (ym != null &&
                                          (_month == null ||
                                              !ym.contains(_month))) {
                                        _month = ym.reduce(math.max);
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            'Months with ideas:',
                            style: appFont(
                              color: colors.mute,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ...monthsInYear.map((m) {
                                final count =
                                    _monthCounts['$_year-$m'] ?? 0;
                                final label =
                                    '${_StreamScreenState._kMonthNames[m - 1]} $_year ($count)';
                                final isSelected =
                                    (!_dateUnknown && _month == m);
                                return _buildChip(
                                  label: label,
                                  isSelected: isSelected,
                                  onTap: () {
                                    setState(() {
                                      _month = m;
                                      _dateUnknown = false;
                                    });
                                  },
                                );
                              }),
                              if (_unknownCount > 0)
                                _buildChip(
                                  label: 'Date unknown ($_unknownCount)',
                                  isSelected: _dateUnknown,
                                  onTap: () {
                                    setState(() {
                                      _dateUnknown = true;
                                      _month = null;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // 2. Sort by
                  Text(
                    'Sort by',
                    style: appFont(
                      color: colors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        label: 'Best first',
                        isSelected: _sort == 'Best first',
                        onTap: () => setState(() => _sort = 'Best first'),
                      ),
                      _buildChip(
                        label: 'Newest first',
                        isSelected: _sort == 'Newest first',
                        onTap: () => setState(() => _sort = 'Newest first'),
                      ),
                      _buildChip(
                        label: 'Oldest first',
                        isSelected: _sort == 'Oldest first',
                        onTap: () => setState(() => _sort = 'Oldest first'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 3. When
                  Text(
                    'When',
                    style: appFont(
                      color: colors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        label: 'Any',
                        isSelected: _when == 'Any',
                        onTap: () => setState(() => _when = 'Any'),
                      ),
                      _buildChip(
                        label: 'Today',
                        isSelected: _when == 'Today',
                        onTap: () => setState(() => _when = 'Today'),
                      ),
                      _buildChip(
                        label: 'Soon',
                        isSelected: _when == 'Soon',
                        onTap: () => setState(() => _when = 'Soon'),
                      ),
                      _buildChip(
                        label: 'Later',
                        isSelected: _when == 'Later',
                        onTap: () => setState(() => _when = 'Later'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 4. Time
                  Text(
                    'Time',
                    style: appFont(
                      color: colors.gold,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildChip(
                        label: 'Any',
                        isSelected: _time == 'Any',
                        onTap: () => setState(() => _time = 'Any'),
                      ),
                      _buildChip(
                        label: 'Quick',
                        isSelected: _time == 'Quick',
                        onTap: () => setState(() => _time = 'Quick'),
                      ),
                      _buildChip(
                        label: 'Medium',
                        isSelected: _time == 'Medium',
                        onTap: () => setState(() => _time = 'Medium'),
                      ),
                      _buildChip(
                        label: 'Long',
                        isSelected: _time == 'Long',
                        onTap: () => setState(() => _time = 'Long'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          Divider(color: colors.line, height: 1),

          // Live button "Show N ideas" & "Clear all"
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _date = 'All time';
                      _month = null;
                      _year = _years.isNotEmpty ? _years.first : null;
                      _dateUnknown = false;
                      _sort = 'Best first';
                      _when = 'Any';
                      _time = 'Any';
                    });
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colors.mute,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                  child: Text(
                    'Clear all',
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        widget.onApply(
                          date: _date,
                          month: _month,
                          year: _year,
                          dateUnknown: _dateUnknown,
                          sort: _sort,
                          when: _when,
                          time: _time,
                        );
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.gold,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Show $matchingCount ${matchingCount == 1 ? 'idea' : 'ideas'}',
                        style: appFont(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TEST HELPER
// ============================================================================
@visibleForTesting
class StreamScreenTestHelper {
  static List<Map<String, dynamic>> applyBucketFilters({
    required List<Map<String, dynamic>> allIdeas,
    required String searchQuery,
    required String date,
    required int? month,
    required int? year,
    required bool dateUnknown,
    required String sort,
    required String when,
    required String time,
  }) {
    return _StreamScreenState._applyBucketFilters(
      allIdeas: allIdeas,
      searchQuery: searchQuery,
      date: date,
      month: month,
      year: year,
      dateUnknown: dateUnknown,
      sort: sort,
      when: when,
      time: time,
    );
  }

  static bool isPlaceholder(Map<String, dynamic> idea) {
    return _StreamScreenState._isPlaceholderIdea(idea);
  }
}
