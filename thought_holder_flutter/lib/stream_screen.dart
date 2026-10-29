import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'thought_provider.dart';
import 'navigation_service.dart';

class StreamScreen extends StatefulWidget {
  const StreamScreen({super.key});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  bool _splitPromptChecked = false;
  String? _deletingForeverId; // For 2-step delete confirm in Trash

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLog149Prompt();
    });
  }

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
        final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
        if (lines.length > 2) {
          _showSplitPromptDialog(log149, box);
        }
      }
    } catch (_) {}
  }

  void _showSplitPromptDialog(Map<String, dynamic> log149, Box box) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1B1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFFBF00), width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.call_split, color: Color(0xFFFFBF00), size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Split LOG-149 into separate ideas?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: const Text(
          'Your long note LOG-149 contains multiple items. Would you like to split it into individual ideas across buckets (e.g., School related, Personal revisions, Personal projects, Others\' projects)?\n\nYour original note will not be deleted.',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 16,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () {
              box.put('log149_split_prompt_shown', true);
              Navigator.pop(ctx);
            },
            child: const Text(
              'Not now',
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              box.put('log149_split_prompt_shown', true);
              Navigator.pop(ctx);
              await _performSplitLog149(log149);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text(
              'Split note',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
      } else if (lower.contains('personal revisions') || lower.contains('revision')) {
        currentBucket = 'Personal revisions';
      } else if (lower.contains('personal projects') || lower.contains('personal project')) {
        currentBucket = 'Personal projects';
      } else if (lower.contains('others projects') || lower.contains("others' projects")) {
        currentBucket = "Others' projects";
      } else {
        bucketed.putIfAbsent(currentBucket, () => []).add(trimmed);
      }
    }

    await provider.splitNoteIntoIdeas(log149['id'], bucketed);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Successfully split note into separate bucketed ideas!'),
          duration: Duration(seconds: 6),
          backgroundColor: Color(0xFF141416),
        ),
      );
    }
  }

  void _showUndoSnackBar(String message, VoidCallback onUndo) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        backgroundColor: const Color(0xFF1B1B1E),
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Colors.white12),
        ),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: const Color(0xFFFFBF00),
          onPressed: onUndo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigationNotifier>();
    final provider = context.watch<ThoughtProvider>();

    return SafeArea(
      child: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 12),
              // Top Pills: Unsorted (count) / Sorted / Done
              _buildTopPills(nav, provider),
              const SizedBox(height: 8),
              // Subtitle
              _buildSubtitle(nav),
              const SizedBox(height: 12),
              // Main Content Area
              Expanded(
                child: nav.isTrashOpen
                    ? _buildTrashScreen(provider, nav)
                    : _buildCurrentTabContent(nav, provider),
              ),
            ],
          ),
          // Floating 3D Trash Button
          Positioned(
            right: 20,
            bottom: 20,
            child: _Floating3DTrashButton(
              trashCount: provider.trashCount,
              isOpen: nav.isTrashOpen,
              onTap: () {
                setState(() => _deletingForeverId = null);
                nav.toggleTrash();
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Subtitle Widget ---
  Widget _buildSubtitle(NavigationNotifier nav) {
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
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  // --- Top Navigation Pills ---
  Widget _buildTopPills(NavigationNotifier nav, ThoughtProvider provider) {
    final unsortedCount = provider.unsortedCount;
    final currentSubTab = nav.streamSubTab;
    final isTrashOpen = nav.isTrashOpen;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPill(
          label: 'Unsorted ($unsortedCount)',
          isSelected: !isTrashOpen && currentSubTab == 'unsorted',
          onTap: () => nav.setStreamSubTab('unsorted'),
        ),
        const SizedBox(width: 8),
        _buildPill(
          label: 'Sorted',
          isSelected: !isTrashOpen && currentSubTab == 'sorted',
          onTap: () => nav.setStreamSubTab('sorted'),
        ),
        const SizedBox(width: 8),
        _buildPill(
          label: 'Done',
          isSelected: !isTrashOpen && currentSubTab == 'done',
          onTap: () => nav.setStreamSubTab('done'),
        ),
      ],
    );
  }

  Widget _buildPill({
    required String label,
    required bool isSelected,
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
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF1E1A08) : const Color(0xFF161618),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFFFBF00)
                    : Colors.white.withOpacity(0.18),
                width: isSelected ? 1.6 : 1.0,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFFBF00) : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Main Content Switcher ---
  Widget _buildCurrentTabContent(NavigationNotifier nav, ThoughtProvider provider) {
    switch (nav.streamSubTab) {
      case 'unsorted':
        return _buildUnsortedTab(provider);
      case 'sorted':
        return _buildSortedTab(nav, provider);
      case 'done':
        return _buildDoneTab(provider);
      default:
        return _buildUnsortedTab(provider);
    }
  }

  // ==========================================
  // TAB 1: UNSORTED TAB
  // ==========================================
  Widget _buildUnsortedTab(ThoughtProvider provider) {
    final unsorted = provider.unsortedThoughts;

    if (unsorted.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.check_circle_outline, size: 56, color: Colors.white24),
              SizedBox(height: 16),
              Text(
                'All caught up!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'No unsorted ideas right now.\nCapture new ideas using voice or text below.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 16, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      itemCount: unsorted.length,
      itemBuilder: (context, index) {
        final thought = unsorted[index];
        return _UnsortedCard(
          key: ValueKey(thought['id']),
          thought: thought,
          buckets: provider.buckets,
          onFile: (bucket) {
            provider.fileThought(thought['id'], bucket);
            _showUndoSnackBar('Filed to $bucket', () {
              provider.unfileThought(thought['id']);
            });
          },
          onMarkDone: () {
            provider.markDone(thought['id'], true);
            _showUndoSnackBar('Marked ${thought['thought_id']} as done', () {
              provider.markDone(thought['id'], false);
            });
          },
          onMoveToTrash: () {
            provider.moveToTrash(thought['id']);
            _showUndoSnackBar('Moved ${thought['thought_id']} to trash', () {
              provider.restoreFromTrash(thought['id']);
            });
          },
          onUpdateContent: (content) {
            provider.updateContent(thought['id'], content);
          },
          onAddNewBucket: (newBucket) async {
            await provider.addBucket(newBucket);
            await provider.fileThought(thought['id'], newBucket);
            _showUndoSnackBar('Filed to $newBucket', () {
              provider.unfileThought(thought['id']);
            });
          },
        );
      },
    );
  }

  // ==========================================
  // TAB 2: SORTED TAB
  // ==========================================
  Widget _buildSortedTab(NavigationNotifier nav, ThoughtProvider provider) {
    if (nav.selectedBucket != null) {
      return _buildBucketDetailView(nav, provider, nav.selectedBucket!);
    }

    final sorted = provider.sortedThoughts;
    final best = provider.bestNextThought;

    if (sorted.isEmpty) {
      final unsortedCount = provider.unsortedCount;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_open, size: 56, color: Colors.white24),
              const SizedBox(height: 16),
              const Text(
                'No sorted ideas yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                unsortedCount > 0
                    ? 'You have $unsortedCount unsorted ideas waiting to be filed into buckets.'
                    : 'File ideas from the Unsorted tab into buckets to see them prioritized here.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 16, height: 1.4),
              ),
              if (unsortedCount > 0) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => nav.setStreamSubTab('unsorted'),
                  icon: const Icon(Icons.inventory_2_outlined, color: Colors.black, size: 18),
                  label: Text(
                    'Go to Unsorted ($unsortedCount)',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFBF00),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      children: [
        // Top: Single Best "Start Here" Card
        if (best != null) ...[
          _StartHereCard(
            thought: best,
            onMarkDone: () {
              provider.markDone(best['id'], true);
              _showUndoSnackBar('Marked ${best['thought_id']} as done', () {
                provider.markDone(best['id'], false);
              });
            },
            onMoveToTrash: () {
              provider.moveToTrash(best['id']);
              _showUndoSnackBar('Moved ${best['thought_id']} to trash', () {
                provider.restoreFromTrash(best['id']);
              });
            },
            onUpdateContent: (c) => provider.updateContent(best['id'], c),
          ),
          const SizedBox(height: 20),
        ],

        // Bucket Tiles Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Buckets',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${provider.buckets.length} total',
              style: const TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Bucket Tiles
        ...provider.buckets.map((bucketName) {
          final ideas = provider.getThoughtsForBucket(bucketName);
          return _BucketTile(
            bucketName: bucketName,
            ideaCount: ideas.length,
            onTap: () => nav.selectBucket(bucketName),
          );
        }),
      ],
    );
  }

  // --- Bucket Detail View ---
  Widget _buildBucketDetailView(
    NavigationNotifier nav,
    ThoughtProvider provider,
    String bucketName,
  ) {
    final ideas = provider.getThoughtsForBucket(bucketName);

    return ListView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      children: [
        // "Back to all buckets" link
        Semantics(
          button: true,
          label: 'Back to all buckets',
          child: InkWell(
            onTap: () => nav.selectBucket(null),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.arrow_back, color: Color(0xFFFFBF00), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Back to all buckets',
                    style: TextStyle(
                      color: Color(0xFFFFBF00),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Bucket Title Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                bucketName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF242428),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                '${ideas.length} ${ideas.length == 1 ? 'idea' : 'ideas'}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (ideas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40.0),
            child: Center(
              child: Text(
                'No ideas in this bucket yet.\nFile ideas from Unsorted to populate this bucket.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 16, height: 1.4),
              ),
            ),
          )
        else
          ...ideas.asMap().entries.map((entry) {
            final int index = entry.key;
            final Map<String, dynamic> idea = entry.value;
            final bool isFirst = (index == 0);

            return _RankedIdeaCard(
              key: ValueKey(idea['id']),
              thought: idea,
              isFirst: isFirst,
              onCycleWhen: () => provider.cycleWhen(idea['id']),
              onCycleTime: () => provider.cycleTime(idea['id']),
              onMarkDone: () {
                provider.markDone(idea['id'], true);
                _showUndoSnackBar('Marked ${idea['thought_id']} as done', () {
                  provider.markDone(idea['id'], false);
                });
              },
              onMoveToTrash: () {
                provider.moveToTrash(idea['id']);
                _showUndoSnackBar('Moved ${idea['thought_id']} to trash', () {
                  provider.restoreFromTrash(idea['id']);
                });
              },
              onUpdateContent: (c) => provider.updateContent(idea['id'], c),
            );
          }),
      ],
    );
  }

  // ==========================================
  // TAB 3: DONE TAB
  // ==========================================
  Widget _buildDoneTab(ThoughtProvider provider) {
    final doneList = provider.doneThoughts;

    if (doneList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.task_alt, size: 56, color: Colors.white24),
              SizedBox(height: 16),
              Text(
                'No completed ideas yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Tap the check icon on any idea to mark it done.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      itemCount: doneList.length,
      itemBuilder: (context, index) {
        final thought = doneList[index];
        return _DoneIdeaCard(
          thought: thought,
          onRestore: () {
            provider.markDone(thought['id'], false);
            _showUndoSnackBar('Restored ${thought['thought_id']} to active', () {
              provider.markDone(thought['id'], true);
            });
          },
          onMoveToTrash: () {
            provider.moveToTrash(thought['id']);
            _showUndoSnackBar('Moved ${thought['thought_id']} to trash', () {
              provider.restoreFromTrash(thought['id']);
            });
          },
        );
      },
    );
  }

  // ==========================================
  // VIEW: TRASH SCREEN
  // ==========================================
  Widget _buildTrashScreen(ThoughtProvider provider, NavigationNotifier nav) {
    final trashedList = provider.trashedThoughts;

    if (trashedList.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.delete_outline, size: 56, color: Colors.white24),
              SizedBox(height: 16),
              Text(
                'Trash is empty',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Trashed ideas will appear here. You can restore them or permanently delete them.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 16, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 100),
      itemCount: trashedList.length,
      itemBuilder: (context, index) {
        final thought = trashedList[index];
        final bool isConfirmingDelete = (_deletingForeverId == thought['id']);

        return _TrashIdeaCard(
          thought: thought,
          isConfirmingDelete: isConfirmingDelete,
          onRestore: () {
            provider.restoreFromTrash(thought['id']);
            _showUndoSnackBar('Restored ${thought['thought_id']}', () {
              provider.moveToTrash(thought['id']);
            });
          },
          onDeleteForeverTap: () {
            if (isConfirmingDelete) {
              provider.deleteForever(thought['id']);
              setState(() => _deletingForeverId = null);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Permanently deleted ${thought['thought_id']}'),
                  duration: const Duration(seconds: 3),
                  backgroundColor: const Color(0xFF1B1B1E),
                ),
              );
            } else {
              setState(() => _deletingForeverId = thought['id']);
            }
          },
        );
      },
    );
  }
}

// ============================================================================
// COMPONENT: FLOATING 3D TRASH BUTTON (Requirement 2)
// ============================================================================
class _Floating3DTrashButton extends StatefulWidget {
  final int trashCount;
  final bool isOpen;
  final VoidCallback onTap;

  const _Floating3DTrashButton({
    Key? key,
    required this.trashCount,
    required this.isOpen,
    required this.onTap,
  }) : super(key: key);

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
        ? const Color(0xFF241C04)
        : const Color(0xFF28282C);

    final borderColor = isGold
        ? const Color(0xFFFFBF00)
        : Colors.white.withOpacity(0.18);

    final iconAndTextColor = isGold
        ? const Color(0xFFFFBF00)
        : Colors.white;

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
          height: size + 6, // extra height for 3D bottom bevel
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
                        style: TextStyle(
                          color: iconAndTextColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Small Red Count Badge (Requirement 2)
              if (hasItems)
                Positioned(
                  top: _isPressed ? 1 : -4,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF0E0E10), width: 2),
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
// COMPONENT: UNSORTED CARD (Requirement 3)
// ============================================================================
class _UnsortedCard extends StatefulWidget {
  final Map<String, dynamic> thought;
  final List<String> buckets;
  final ValueChanged<String> onFile;
  final VoidCallback onMarkDone;
  final VoidCallback onMoveToTrash;
  final ValueChanged<String> onUpdateContent;
  final ValueChanged<String> onAddNewBucket;

  const _UnsortedCard({
    Key? key,
    required this.thought,
    required this.buckets,
    required this.onFile,
    required this.onMarkDone,
    required this.onMoveToTrash,
    required this.onUpdateContent,
    required this.onAddNewBucket,
  }) : super(key: key);

  @override
  State<_UnsortedCard> createState() => _UnsortedCardState();
}

class _UnsortedCardState extends State<_UnsortedCard> {
  bool _isEditing = false;
  bool _isAddingBucket = false;
  late TextEditingController _editController;
  late TextEditingController _newBucketController;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController(text: widget.thought['content'] ?? '');
    _newBucketController = TextEditingController();
  }

  @override
  void dispose() {
    _editController.dispose();
    _newBucketController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thoughtId = widget.thought['thought_id'] as String? ?? 'LOG';
    final content = widget.thought['content'] as String? ?? '';

    return Card(
      color: const Color(0xFF18181B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2B2B30), width: 1.2),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Gold LOG Number + 3 Card Icons (min 44px touch targets)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  thoughtId,
                  style: const TextStyle(
                    color: Color(0xFFFFBF00),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                Row(
                  children: [
                    // Green Check: Mark done (Requirement 6)
                    Semantics(
                      button: true,
                      label: 'Mark done',
                      child: IconButton(
                        icon: const Icon(
                          Icons.check_circle_outline,
                          color: Color(0xFF34D399),
                          size: 22,
                        ),
                        tooltip: 'Mark done',
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        padding: EdgeInsets.zero,
                        onPressed: widget.onMarkDone,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Trash Can: Move to trash (Requirement 6)
                    Semantics(
                      button: true,
                      label: 'Move to trash',
                      child: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white60,
                          size: 20,
                        ),
                        tooltip: 'Move to trash',
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        padding: EdgeInsets.zero,
                        onPressed: widget.onMoveToTrash,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Pencil: Edit text inline (Requirement 6)
                    Semantics(
                      button: true,
                      label: 'Edit text',
                      child: IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white60,
                          size: 20,
                        ),
                        tooltip: 'Edit text',
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() {
                            _isEditing = !_isEditing;
                            if (_isEditing) {
                              _editController.text = widget.thought['content'] ?? '';
                            }
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Content or Inline Edit
            if (_isEditing) ...[
              TextField(
                controller: _editController,
                maxLines: null,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Edit your thought...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF222226),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFFFBF00)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFFFBF00), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _isEditing = false),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 15)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final updated = _editController.text.trim();
                      if (updated.isNotEmpty) {
                        widget.onUpdateContent(updated);
                      }
                      setState(() => _isEditing = false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBF00),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            ] else ...[
              Text(
                content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // "Which bucket?" prompt (Requirement 3)
            const Text(
              'Which bucket?',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),

            // Bucket Buttons + "+ New bucket"
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ...widget.buckets.map((b) => _BucketPillButton(
                      label: b,
                      onTap: () => widget.onFile(b),
                    )),
                _DashedNewBucketPill(
                  onTap: () => setState(() => _isAddingBucket = !_isAddingBucket),
                ),
              ],
            ),

            // Inline "+ New bucket" input box (Requirement 3)
            if (_isAddingBucket) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF222226),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFBF00), width: 1.2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _newBucketController,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: const InputDecoration(
                        hintText: 'New bucket name...',
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            _newBucketController.clear();
                            setState(() => _isAddingBucket = false);
                          },
                          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final name = _newBucketController.text.trim();
                            if (name.isNotEmpty) {
                              widget.onAddNewBucket(name);
                              _newBucketController.clear();
                              setState(() => _isAddingBucket = false);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFBF00),
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('Save bucket', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Bucket Pill Button (Requirement 3: Large tappable button with gold outline)
class _BucketPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BucketPillButton({Key? key, required this.label, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'File in $label',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFFFBF00), width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Dashed "+ New bucket" Pill Button
class _DashedNewBucketPill extends StatelessWidget {
  final VoidCallback onTap;

  const _DashedNewBucketPill({Key? key, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Create new bucket',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: const Color(0xFFFFBF00).withOpacity(0.8),
              strokeWidth: 1.4,
              radius: 22,
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              alignment: Alignment.center,
              child: const Text(
                '+ New bucket',
                style: TextStyle(
                  color: Color(0xFFFFBF00),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(strokeWidth / 2, strokeWidth / 2, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    const double dashLength = 5.0;
    const double dashGap = 4.0;

    for (final metric in metrics) {
      double distance = 0.0;
      while (distance < metric.length) {
        final length = math.min(dashLength, metric.length - distance);
        final extract = metric.extractPath(distance, distance + length);
        canvas.drawPath(extract, paint);
        distance += dashLength + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color;
}

// ============================================================================
// COMPONENT: START HERE CARD (Requirement 4)
// ============================================================================
class _StartHereCard extends StatefulWidget {
  final Map<String, dynamic> thought;
  final VoidCallback onMarkDone;
  final VoidCallback onMoveToTrash;
  final ValueChanged<String> onUpdateContent;

  const _StartHereCard({
    Key? key,
    required this.thought,
    required this.onMarkDone,
    required this.onMoveToTrash,
    required this.onUpdateContent,
  }) : super(key: key);

  @override
  State<_StartHereCard> createState() => _StartHereCardState();
}

class _StartHereCardState extends State<_StartHereCard> {
  bool _isEditing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.thought['content'] ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thought = widget.thought;
    final thoughtId = thought['thought_id'] as String? ?? 'LOG';
    final content = thought['content'] as String? ?? '';
    final bucket = thought['bucket'] as String? ?? 'General';
    final reason = RankingEngine.getReason(thought);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFBF00), width: 1.8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFBF00).withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: "★ Start here" badge + Bucket tag + Icons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFBF00),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '★ START HERE',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF28282C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      bucket,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    thoughtId,
                    style: const TextStyle(
                      color: Color(0xFFFFBF00),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white60, size: 20),
                    tooltip: 'Move to trash',
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: widget.onMoveToTrash,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.white60, size: 20),
                    tooltip: 'Edit text',
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () {
                      setState(() {
                        _isEditing = !_isEditing;
                        if (_isEditing) _controller.text = content;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Content
          if (_isEditing) ...[
            TextField(
              controller: _controller,
              maxLines: null,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF222226),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => setState(() => _isEditing = false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () {
                    widget.onUpdateContent(_controller.text.trim());
                    setState(() => _isEditing = false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFBF00),
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ] else ...[
            Text(
              content,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Plain-language reason (Requirement 4)
          Row(
            children: [
              const Icon(Icons.bolt, size: 16, color: Color(0xFFFFBF00)),
              const SizedBox(width: 6),
              Text(
                reason,
                style: const TextStyle(
                  color: Color(0xFFFFBF00),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // "Mark done" Prominent Button (Requirement 4)
          ElevatedButton.icon(
            onPressed: widget.onMarkDone,
            icon: const Icon(Icons.check_circle, color: Colors.black, size: 20),
            label: const Text(
              'Mark done',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFBF00),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// COMPONENT: BUCKET TILE (Requirement 4)
// ============================================================================
class _BucketTile extends StatelessWidget {
  final String bucketName;
  final int ideaCount;
  final VoidCallback onTap;

  const _BucketTile({
    Key? key,
    required this.bucketName,
    required this.ideaCount,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$bucketName, $ideaCount ideas',
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: const Color(0xFF1B1B1E),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF26262B),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.folder_outlined,
                      color: Color(0xFFFFBF00),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bucketName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$ideaCount ${ideaCount == 1 ? 'idea' : 'ideas'}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white38,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// COMPONENT: RANKED IDEA CARD (Requirement 4 & 5)
// ============================================================================
class _RankedIdeaCard extends StatefulWidget {
  final Map<String, dynamic> thought;
  final bool isFirst;
  final VoidCallback onCycleWhen;
  final VoidCallback onCycleTime;
  final VoidCallback onMarkDone;
  final VoidCallback onMoveToTrash;
  final ValueChanged<String> onUpdateContent;

  const _RankedIdeaCard({
    Key? key,
    required this.thought,
    required this.isFirst,
    required this.onCycleWhen,
    required this.onCycleTime,
    required this.onMarkDone,
    required this.onMoveToTrash,
    required this.onUpdateContent,
  }) : super(key: key);

  @override
  State<_RankedIdeaCard> createState() => _RankedIdeaCardState();
}

class _RankedIdeaCardState extends State<_RankedIdeaCard> {
  bool _isEditing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.thought['content'] ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final thought = widget.thought;
    final thoughtId = thought['thought_id'] as String? ?? 'LOG';
    final content = thought['content'] as String? ?? '';
    final whenVal = thought['when_val'] as String? ?? 'Soon';
    final timeVal = thought['time_val'] as String? ?? 'Medium';
    final reason = RankingEngine.getReason(thought);

    return Card(
      color: const Color(0xFF18181B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: widget.isFirst
              ? const Color(0xFFFFBF00)
              : Colors.white.withOpacity(0.08),
          width: widget.isFirst ? 1.6 : 1.0,
        ),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (widget.isFirst) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFBF00),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          '★ Start here',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    Text(
                      thoughtId,
                      style: const TextStyle(
                        color: Color(0xFFFFBF00),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Green Check: Mark done (Requirement 6)
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline, color: Color(0xFF34D399), size: 22),
                      tooltip: 'Mark done',
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      onPressed: widget.onMarkDone,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white60, size: 20),
                      tooltip: 'Move to trash',
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      onPressed: widget.onMoveToTrash,
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.white60, size: 20),
                      tooltip: 'Edit text',
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      onPressed: () {
                        setState(() {
                          _isEditing = !_isEditing;
                          if (_isEditing) _controller.text = content;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Content or Inline Edit
            if (_isEditing) ...[
              TextField(
                controller: _controller,
                maxLines: null,
                style: const TextStyle(color: Colors.white, fontSize: 18),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFF222226),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _isEditing = false),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      widget.onUpdateContent(_controller.text.trim());
                      setState(() => _isEditing = false);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFBF00),
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ] else ...[
              Text(
                content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Plain-Language Reason
            Text(
              reason,
              style: const TextStyle(
                color: Color(0xFFFFBF00),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 14),

            // Cycle Buttons: When & Time (Requirement 4 & 5)
            Row(
              children: [
                _CycleButton(
                  label: 'When: $whenVal',
                  tooltip: 'Tap to cycle: Today -> Soon -> Later',
                  onTap: widget.onCycleWhen,
                  accentColor: whenVal == 'Today'
                      ? const Color(0xFFFFBF00)
                      : (whenVal == 'Soon' ? Colors.white : Colors.white60),
                ),
                const SizedBox(width: 10),
                _CycleButton(
                  label: 'Time: $timeVal',
                  tooltip: 'Tap to cycle: Quick -> Medium -> Long',
                  onTap: widget.onCycleTime,
                  accentColor: timeVal == 'Quick'
                      ? const Color(0xFF34D399)
                      : (timeVal == 'Medium' ? const Color(0xFFFFBF00) : Colors.white60),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CycleButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color accentColor;

  const _CycleButton({
    Key? key,
    required this.label,
    required this.tooltip,
    required this.onTap,
    required this.accentColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $tooltip',
      child: Material(
        color: const Color(0xFF242428),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withOpacity(0.5), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.sync, size: 14, color: accentColor.withOpacity(0.7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// COMPONENT: DONE IDEA CARD (Requirement 6 & 10)
// ============================================================================
class _DoneIdeaCard extends StatelessWidget {
  final Map<String, dynamic> thought;
  final VoidCallback onRestore;
  final VoidCallback onMoveToTrash;

  const _DoneIdeaCard({
    Key? key,
    required this.thought,
    required this.onRestore,
    required this.onMoveToTrash,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final thoughtId = thought['thought_id'] as String? ?? 'LOG';
    final content = thought['content'] as String? ?? '';
    final bucket = thought['bucket'] as String? ?? '';

    return Card(
      color: const Color(0xFF161618),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF26262B)),
      ),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF34D399), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      thoughtId,
                      style: const TextStyle(
                        color: Color(0xFFFFBF00),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (bucket.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· $bucket',
                        style: const TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white54, size: 20),
                  tooltip: 'Move to trash',
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  onPressed: onMoveToTrash,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 18,
                decoration: TextDecoration.lineThrough,
                decorationColor: Colors.white38,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRestore,
              icon: const Icon(Icons.undo, size: 16, color: Color(0xFFFFBF00)),
              label: const Text(
                'Mark active',
                style: TextStyle(color: Color(0xFFFFBF00), fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFFBF00)),
                minimumSize: const Size(130, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// COMPONENT: TRASH IDEA CARD (Requirement 7)
// ============================================================================
class _TrashIdeaCard extends StatelessWidget {
  final Map<String, dynamic> thought;
  final bool isConfirmingDelete;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForeverTap;

  const _TrashIdeaCard({
    Key? key,
    required this.thought,
    required this.isConfirmingDelete,
    required this.onRestore,
    required this.onDeleteForeverTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final thoughtId = thought['thought_id'] as String? ?? 'LOG';
    final content = thought['content'] as String? ?? '';
    final bucket = thought['bucket'] as String? ?? '';

    return Card(
      color: const Color(0xFF161618),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2A2A2E)),
      ),
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Text(
                  thoughtId,
                  style: const TextStyle(
                    color: Color(0xFFFFBF00),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (bucket.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '· $bucket',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              content,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 18,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),

            // Plain words: Restore and Delete forever (Requirement 7 & 10)
            Row(
              children: [
                // Restore Button
                OutlinedButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(Icons.restore, size: 18, color: Color(0xFFFFBF00)),
                  label: const Text(
                    'Restore',
                    style: TextStyle(
                      color: Color(0xFFFFBF00),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFFBF00), width: 1.2),
                    minimumSize: const Size(120, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Delete Forever Button (2-step confirm)
                Expanded(
                  child: ElevatedButton(
                    onPressed: onDeleteForeverTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isConfirmingDelete
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF26262B),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(140, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isConfirmingDelete
                              ? const Color(0xFFEF4444)
                              : Colors.white24,
                        ),
                      ),
                    ),
                    child: Text(
                      isConfirmingDelete
                          ? 'Tap again to delete forever'
                          : 'Delete forever',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isConfirmingDelete ? 13 : 14,
                        fontWeight: FontWeight.bold,
                        color: isConfirmingDelete ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
