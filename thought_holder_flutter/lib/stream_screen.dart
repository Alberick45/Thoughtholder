import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'thought_provider.dart';
import 'navigation_service.dart';
import 'settings_service.dart';
import 'sound_service.dart';
import 'app_theme.dart';
import 'idea_detail_screen.dart';
import 'notifications_settings_screen.dart';
import 'utils/title_generator.dart';

class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  bool _splitPromptChecked = false;
  int _visibleBucketIdeasCount = 20;
  int _visibleDoneCount = 9; // UPDATE 3: 9 at a time (3x3)
  int _visibleTrashCount = 12;
  String? _deletingForeverId; // For 2-step delete confirmation in Trash

  // UPDATE 3: Bucket slider & search state
  String _bucketSearchQuery = '';
  final TextEditingController _bucketSearchController = TextEditingController();
  final PageController _bucketPageController = PageController();
  int _bucketCurrentPage = 0;

  // UPDATE 3: Done search state
  String _doneSearchQuery = '';
  final TextEditingController _doneSearchController = TextEditingController();

  @override
  void dispose() {
    _bucketSearchController.dispose();
    _bucketPageController.dispose();
    _doneSearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLog149Prompt();
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

  // --- 6-Second Undo Toast (Requirement 1) ---
  void _showUndoSnackBar(String message, VoidCallback onUndo) {
    final settings = context.read<SettingsService>();
    final colors = AppColors.of(settings.theme);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: appFont(color: colors.text, fontSize: 15),
        ),
        backgroundColor: colors.card,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.line),
        ),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: colors.gold,
          onPressed: () {
            SoundService.instance.play(SoundEvent.undo, settings: settings);
            onUndo();
          },
        ),
      ),
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

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 12),
              // First-time sound choice card (Section 2)
              if (!settings.soundPromptAnswered) ...[
                _buildSoundChoiceCard(settings, colors),
                const SizedBox(height: 10),
              ],
              // Top Navigation Pills: Unsorted (N) / Sorted / Done
              _buildTopPills(nav, provider, colors, settings),
              const SizedBox(height: 8),
              // Subtitle
              _buildSubtitle(nav, colors),
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
    );
  }

  // --- Subtitle Widget (Plain words, sentence case) ---
  Widget _buildSubtitle(NavigationNotifier nav, AppColors colors) {
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
              ? 'Ideas grouped by bucket and ranked by priority.'
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

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Sorted tab first
        _buildPill(
          label: 'Sorted',
          isSelected: !isTrashOpen && currentSubTab == 'sorted',
          colors: colors,
          onTap: () {
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
          isSelected: !isTrashOpen && currentSubTab == 'unsorted',
          colors: colors,
          onTap: () {
            if (currentSubTab != 'unsorted' || isTrashOpen) {
              SoundService.instance.play(SoundEvent.tabSwitch, settings: settings);
            }
            nav.setStreamSubTab('unsorted');
          },
        ),
        // Done tab removed per user request
      ],
    );
  }

  Widget _buildPill({
    required String label,
    required bool isSelected,
    required AppColors colors,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
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

  // --- Main Content Switcher ---
  Widget _buildCurrentTabContent(
    NavigationNotifier nav,
    ThoughtProvider provider,
    SettingsService settings,
    AppColors colors,
  ) {
    switch (nav.streamSubTab) {
      case 'unsorted':
        return _buildUnsortedTab(provider, nav, colors);
      case 'sorted':
        return _buildSortedTab(nav, provider, settings, colors);
      case 'done':
        return _buildDoneTab(provider, colors);
      default:
        return _buildUnsortedTab(provider, nav, colors);
    }
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
                      side: BorderSide(color: colors.bad.withOpacity(0.5)),
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
  // TAB 2: SORTED TAB (Section 4)
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

    final sorted = provider.sortedThoughts;
    final best = provider.bestNextThought;
    final orderedBuckets = provider.getOrderedBuckets(settings.bucketOrder);

    if (sorted.isEmpty && orderedBuckets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open, size: 64, color: colors.mute),
              const SizedBox(height: 16),
              Text(
                'No sorted ideas yet',
                style: appFont(
                  color: colors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'File ideas from the Unsorted tab into buckets to see them prioritized here.',
                textAlign: TextAlign.center,
                style: appFont(color: colors.mute, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => nav.setStreamSubTab('unsorted'),
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Go to Unsorted ideas'),
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

    return ListView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      children: [
        // Skippable Onboarding Card (UPDATE 5 - Section D)
        if (!settings.hasSeenStartHereOnboardingPrompt && sorted.isNotEmpty) ...[
          _buildStartHereOnboardingCard(context, settings, colors),
          const SizedBox(height: 16),
        ],

        // Top "Start here" Card across all buckets (Section 4)
        if (best != null) ...[
          _buildStartHereCard(best, provider, colors),
          const SizedBox(height: 20),
        ],

        // Buckets Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Buckets',
              style: appFont(
                color: colors.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                Text(
                  '${orderedBuckets.length} total',
                  style: appFont(color: colors.mute, fontSize: 13),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () =>
                      _showCreateBucketDialog(context, provider, colors),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: [
                        Icon(Icons.add, color: colors.gold, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'New bucket',
                          style: appFont(
                            color: colors.gold,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Bucket Search Bar (Section A.2)
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.line),
          ),
          child: TextField(
            controller: _bucketSearchController,
            onChanged: (val) {
              setState(() {
                _bucketSearchQuery = val.trim();
                _bucketCurrentPage = 0;
              });
              if (_bucketPageController.hasClients) {
                _bucketPageController.jumpToPage(0);
              }
            },
            style: appFont(color: colors.text, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Search buckets...',
              hintStyle: appFont(color: colors.mute, fontSize: 14),
              prefixIcon: Icon(Icons.search, color: colors.mute, size: 20),
              suffixIcon: _bucketSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, color: colors.mute, size: 18),
                      onPressed: () {
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
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2-at-a-time Slider with Search (Section A.2)
        Builder(
          builder: (ctx) {
            final matchingBuckets = orderedBuckets.where((b) {
              if (_bucketSearchQuery.isEmpty) return true;
              final name = (b['name'] as String).toLowerCase();
              return name.contains(_bucketSearchQuery.toLowerCase());
            }).toList();

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

            // Append "+ New bucket" card if not searching
            if (_bucketSearchQuery.isEmpty) {
              cards.add(
                InkWell(
                  onTap: () =>
                      _showCreateBucketDialog(context, provider, colors),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.card.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.gold.withOpacity(0.6),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 28, color: colors.gold),
                        const SizedBox(height: 6),
                        Text(
                          'New bucket',
                          style: appFont(
                            color: colors.gold,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

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
                if (pageCount > 1) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Showing ${safeCurrentPage * 2 + 1}-${math.min((safeCurrentPage + 1) * 2, cards.length)} of ${cards.length}',
                        style: appFont(color: colors.mute, fontSize: 12),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.arrow_back_ios_new,
                              size: 16,
                              color: safeCurrentPage > 0
                                  ? colors.gold
                                  : colors.mute.withOpacity(0.3),
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
                                  : colors.mute.withOpacity(0.3),
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
                ],

                // 2-at-a-time Slider
                SizedBox(
                  height: 135,
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

  // --- Skippable Start Here Onboarding Card (UPDATE 5 - Section D) ---
  Widget _buildStartHereOnboardingCard(
    BuildContext context,
    SettingsService settings,
    AppColors colors,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.gold, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_outline, color: colors.gold, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Want a nudge to tell you what to start with?',
                  style: appFont(
                    color: colors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'We can send you a gentle reminder with your top-priority idea at predictable times.',
            style: appFont(color: colors.mute, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      settings.setSeenStartHereOnboardingPrompt();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationsSettingsScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Yes, set it up',
                      style: appFont(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () {
                      settings.setSeenStartHereOnboardingPrompt();
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: colors.line),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'No thanks',
                      style: appFont(
                        color: colors.mute,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
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

  // --- Top "Start here" Card for Sorted View ---
  Widget _buildStartHereCard(
    Map<String, dynamic> thought,
    ThoughtProvider provider,
    AppColors colors,
  ) {
    final settings = context.read<SettingsService>();
    final ideaName = TitleGenerator.getIdeaName(thought);
    final timestamp = IdeaFormatters.formatReadableTimestamp(thought['created_at'] as int?);
    final captureIcon = IdeaFormatters.getCaptureIcon(thought['audio_path'] ?? thought['type']);
    final bucketName = thought['bucket'] as String? ?? 'General';
    final iconKey = provider.getBucketIcon(bucketName);
    final iconData = kBucketIcons[iconKey] ?? Icons.folder_outlined;
    final reason = RankingEngine.getReason(thought);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.gold, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: colors.gold.withOpacity(0.08),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: "★ Start here" gold badge + Idea Name + Timestamp + Bucket Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.gold,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '★ Start here',
                            style: appFont(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.goldBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.gold.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconData, size: 14, color: colors.gold),
                    const SizedBox(width: 5),
                    Text(
                      bucketName,
                      style: appFont(
                        color: colors.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Capped Text (3 lines, Read more)
          _CappedText(
            text: thought['content'] as String? ?? '',
            colors: colors,
            fontSize: 16,
          ),
          const SizedBox(height: 8),

          // Plain reason line (Sentence case, plain English)
          Text(
            reason,
            style: appFont(
              color: colors.mute,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 14),

          // Visible Action Buttons (Icon + Text, >=48px target)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    provider.markDone(thought['id'], true);
                    SoundService.instance.play(SoundEvent.done, settings: settings);
                    _showUndoSnackBar('Marked "$ideaName" as done', () {
                      provider.markDone(thought['id'], false);
                    });
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Mark done'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.done,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () {
                  provider.moveToTrash(thought['id']);
                  SoundService.instance.play(SoundEvent.trash, settings: settings);
                  _showUndoSnackBar('Moved "$ideaName" to trash', () {
                    provider.restoreFromTrash(thought['id']);
                  });
                },
                icon: Icon(Icons.delete_outline, size: 18, color: colors.bad),
                label: Text(
                  'Trash',
                  style: appFont(color: colors.bad, fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.bad.withOpacity(0.5)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: Icon(Icons.more_vert, color: colors.mute),
                tooltip: 'More options',
                onPressed: () =>
                    _showIdeaContextMenu(context, provider, thought, colors),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Drill-Down Bucket View (Section 4) ---
  Widget _buildBucketDetailView(
    NavigationNotifier nav,
    ThoughtProvider provider,
    SettingsService settings,
    String bucketName,
    AppColors colors,
  ) {
    final ideas = provider.getThoughtsForBucket(bucketName);
    final iconKey = provider.getBucketIcon(bucketName);
    final iconData = kBucketIcons[iconKey] ?? Icons.folder_outlined;

    final visibleCount = math.min(_visibleBucketIdeasCount, ideas.length);
    final visibleIdeas = ideas.take(visibleCount).toList();

    return ListView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      children: [
        // "‹ Back to all buckets" Button (Visible, min 48px height)
        Semantics(
          button: true,
          label: 'Back to all buckets',
          child: InkWell(
            onTap: () {
              setState(() => _visibleBucketIdeasCount = 20);
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
                  Icon(Icons.arrow_back, color: colors.gold, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Back to all buckets',
                    style: appFont(
                      color: colors.gold,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Bucket Title Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(iconData, size: 24, color: colors.gold),
                const SizedBox(width: 10),
                Text(
                  bucketName,
                  style: appFont(
                    color: colors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.line),
              ),
              child: Text(
                '${ideas.length} ${ideas.length == 1 ? 'idea' : 'ideas'}',
                style: appFont(color: colors.mute, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // UPDATE 6 - Section C: Spreading ideas out card (>= 25 ideas)
        if (ideas.length >= 25 && !settings.isBucketSplitDismissed(bucketName)) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.gold.withOpacity(0.5), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.call_split, color: colors.gold, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This bucket is getting big. Want to split it into a new bucket?',
                        style: appFont(
                          color: colors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            await settings.dismissBucketSplit(bucketName);
                            if (mounted) {
                              setState(() {});
                              _showCreateBucketDialog(context, provider, colors);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.gold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Make a new bucket',
                            style: appFont(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () async {
                          await settings.dismissBucketSplit(bucketName);
                          setState(() {});
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Not now',
                          style: appFont(
                            color: colors.mute,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (ideas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40.0),
            child: Center(
              child: Text(
                'No ideas in this bucket yet.\nFile ideas from Unsorted to populate this bucket.',
                textAlign: TextAlign.center,
                style: appFont(color: colors.mute, fontSize: 16, height: 1.4),
              ),
            ),
          )
        else ...[
          ...visibleIdeas.asMap().entries.map((entry) {
            final int index = entry.key;
            final Map<String, dynamic> idea = entry.value;
            final bool isFirst = (index == 0);

            final bool isDesktop = (!kIsWeb &&
                    (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) ||
                MediaQuery.of(context).size.width >= 600;

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
          if (ideas.length > visibleCount) ...[
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
                  'Show more ideas (${ideas.length - visibleCount} remaining)',
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

  // --- Ranked Idea Card in Drill-Down Bucket View ---
  Widget _buildRankedIdeaCard({
    required Map<String, dynamic> idea,
    required bool isFirst,
    required ThoughtProvider provider,
    required AppColors colors,
    required SettingsService settings,
    required bool isDesktop,
  }) {
    final whenVal = idea['when_val'] as String? ?? 'Soon';
    final timeVal = idea['time_val'] as String? ?? 'Medium';
    final reason = RankingEngine.getReason(idea);
    final ideaName = TitleGenerator.getIdeaName(idea);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Fixed height idea card (same card as Unsorted)
          SizedBox(
            height: isDesktop ? 220.0 : 200.0,
            child: FixedIdeaCard(
              idea: idea,
              colors: colors,
              provider: provider,
              isFirst: isFirst,
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
            ),
          ),
          const SizedBox(height: 6),

          // Plain Reason Line
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              reason,
              style: appFont(
                color: colors.mute,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Priority Cycle Buttons (When and Time, min 48px height)
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => provider.cycleWhen(idea['id']),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.line),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.schedule, size: 15, color: colors.gold),
                        const SizedBox(width: 6),
                        Text(
                          'When: $whenVal',
                          style: appFont(
                            color: colors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => provider.cycleTime(idea['id']),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.line),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.timer_outlined, size: 15, color: colors.gold),
                        const SizedBox(width: 6),
                        Text(
                          'Time: $timeVal',
                          style: appFont(
                            color: colors.text,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Visible Action Buttons: [✓ Mark done] and [🗑 Trash]
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      provider.markDone(idea['id'], true);
                      SoundService.instance.play(SoundEvent.done, settings: settings);
                      _showUndoSnackBar('Marked "$ideaName" as done', () {
                        provider.markDone(idea['id'], false);
                      });
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Mark done'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.done,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    provider.moveToTrash(idea['id']);
                    SoundService.instance.play(SoundEvent.trash, settings: settings);
                    _showUndoSnackBar('Moved "$ideaName" to trash', () {
                      provider.restoreFromTrash(idea['id']);
                    });
                  },
                  icon: Icon(Icons.delete_outline, size: 16, color: colors.bad),
                  label: Text(
                    'Trash',
                    style: appFont(color: colors.bad, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colors.bad.withOpacity(0.5)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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
  // TAB 3: DONE TAB (Section 5: Green File Icons Grid + Peek Sheet)
  // ==========================================================================
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
                          color: colors.done.withOpacity(0.35),
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
                    side: BorderSide(color: colors.bad.withOpacity(0.5)),
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
  void _showCreateBucketDialog(
    BuildContext context,
    ThoughtProvider provider,
    AppColors colors, {
    String? fileThoughtId,
  }) {
    final nameController = TextEditingController();
    String selectedIcon = 'folder';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: colors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: colors.gold, width: 1.5),
            ),
            title: Text(
              'New bucket',
              style: appFont(
                color: colors.text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
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
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: appFont(color: colors.mute)),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    Navigator.pop(ctx);
                    await provider.addBucket(name, icon: selectedIcon);
                    final settings = context.read<SettingsService>();
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
          );
        },
      ),
    );
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Rename bucket',
            style: appFont(color: colors.text, fontWeight: FontWeight.bold)),
        content: TextField(
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: appFont(color: colors.mute)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != oldName) {
                Navigator.pop(ctx);
                await provider.renameBucket(oldName, newName);
                final settings = context.read<SettingsService>();
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
    );
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

  // --- Idea Context Menu (Section D: Exact 7 buttons in order) ---
  void _showIdeaContextMenu(
    BuildContext context,
    ThoughtProvider provider,
    Map<String, dynamic> idea,
    AppColors colors,
  ) {
    final ideaName = TitleGenerator.getIdeaName(idea);
    final timestamp = IdeaFormatters.formatReadableTimestamp(idea['created_at'] as int?);
    final captureIcon = IdeaFormatters.getCaptureIcon(idea['audio_path'] ?? idea['type']);
    final content = idea['content'] as String? ?? '';

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
            // 1. Edit
            SizedBox(
              height: 48,
              child: InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditIdeaDialog(context, provider, idea, colors);
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: colors.text, size: 20),
                      const SizedBox(width: 14),
                      Text('Edit',
                          style: appFont(color: colors.text, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
            // 2. Copy
            SizedBox(
              height: 48,
              child: InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: content));
                  _showUndoSnackBar('Copied "$ideaName" to clipboard', () {});
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.copy_outlined, color: colors.text, size: 20),
                      const SizedBox(width: 14),
                      Text('Copy',
                          style: appFont(color: colors.text, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
            // 3. Move to another bucket
            SizedBox(
              height: 48,
              child: InkWell(
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
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.drive_file_move_outlined,
                          color: colors.text, size: 20),
                      const SizedBox(width: 14),
                      Text('Move to another bucket',
                          style: appFont(color: colors.text, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
            // 4. Move back to Unsorted
            SizedBox(
              height: 48,
              child: InkWell(
                onTap: () {
                  final oldBucket = idea['bucket'] as String?;
                  Navigator.pop(ctx);
                  provider.unfileThought(idea['id']);
                  final s = context.read<SettingsService>();
                  SoundService.instance.play(SoundEvent.drop, settings: s);
                  _showUndoSnackBar('Moved "$ideaName" back to Unsorted', () {
                    if (oldBucket != null && oldBucket.isNotEmpty) {
                      provider.fileThought(idea['id'], oldBucket);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.inbox_outlined, color: colors.text, size: 20),
                      const SizedBox(width: 14),
                      Text('Move back to Unsorted',
                          style: appFont(color: colors.text, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
            // 5. Mark done
            SizedBox(
              height: 48,
              child: InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  provider.markDone(idea['id'], true);
                  final s = context.read<SettingsService>();
                  SoundService.instance.play(SoundEvent.done, settings: s);
                  _showUndoSnackBar('Marked "$ideaName" as done', () {
                    provider.markDone(idea['id'], false);
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: colors.done, size: 20),
                      const SizedBox(width: 14),
                      Text(
                        'Mark done',
                        style: appFont(
                          color: colors.done,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 6. Move to Trash
            SizedBox(
              height: 48,
              child: InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  provider.moveToTrash(idea['id']);
                  final s = context.read<SettingsService>();
                  SoundService.instance.play(SoundEvent.trash, settings: s);
                  _showUndoSnackBar('Moved "$ideaName" to trash', () {
                    provider.restoreFromTrash(idea['id']);
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline,
                          color: colors.bad, size: 20),
                      const SizedBox(width: 14),
                      Text(
                        'Move to Trash',
                        style: appFont(
                          color: colors.bad,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 12),
            // 7. Cancel
            SizedBox(
              height: 48,
              child: InkWell(
                onTap: () => Navigator.pop(ctx),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(Icons.close, color: colors.mute, size: 20),
                      const SizedBox(width: 14),
                      Text('Cancel',
                          style: appFont(color: colors.mute, fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

              try {
                // One-step save: create if needed (never creating a duplicate), move idea, save, then close.
                final canonicalName = await provider.addBucket(targetBucket);
                final destination =
                    canonicalName.isNotEmpty ? canonicalName : targetBucket;

                final oldBucket = idea['bucket'] as String?;
                await provider.fileThought(idea['id'], destination);

                final s = context.read<SettingsService>();
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
                final s = context.read<SettingsService>();
                SoundService.instance.play(SoundEvent.error, settings: s);
                setPopupState(() {
                  isAdding = false;
                  errorMessage =
                      'Could not move idea to bucket. Please try again.';
                });
              }
            }

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              decoration: BoxDecoration(
                color: colors.bg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                border: Border.all(color: colors.line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Pinned Heading with Close Button
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
                              'Adding "$ideaName" to…',
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

                  // "Find or create a bucket" Field
                  Container(
                    height: 48,
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
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage!,
                      style: appFont(color: colors.bad, fontSize: 13),
                    ),
                  ],

                  if (isAdding) ...[
                    const SizedBox(height: 14),
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

                  const SizedBox(height: 12),

                  // Scrolling List of Buckets + Create Row
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        // Create row
                        if (showCreateRow) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: colors.gold.withOpacity(0.6)),
                            ),
                            child: SizedBox(
                              height: 48,
                              child: InkWell(
                                onTap: isAdding
                                    ? null
                                    : () => onSelectBucket(trimmedQuery),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
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
                          ),
                        ],

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
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: colors.line),
                            ),
                            child: SizedBox(
                              height: 48,
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
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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

            // Subtitle row: timestamp, capture icon, bucket, small LOG id
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: colors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.gold, width: 1.5),
          ),
          title: Row(
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
          content: SizedBox(
            width: double.maxFinite,
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
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            SizedBox(
              height: 48,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(ctx),
                icon: Icon(Icons.close, color: colors.mute, size: 18),
                label: Text('Cancel', style: appFont(color: colors.mute)),
              ),
            ),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final newContent = contentController.text.trim();
                  final newTitle = titleController.text.trim();
                  if (newContent.isNotEmpty) {
                    Navigator.pop(ctx);
                    final now = DateTime.now().millisecondsSinceEpoch;
                    if (newTitle.isNotEmpty && newTitle != currentTitle) {
                      await provider.updateThoughtTitle(idea['id'], newTitle, titleSource: 'user');
                    }
                    await provider.updateContent(idea['id'], newContent, editedAt: now);
                    final s = context.read<SettingsService>();
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
    );
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
                        color: Colors.black.withOpacity(0.55),
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
