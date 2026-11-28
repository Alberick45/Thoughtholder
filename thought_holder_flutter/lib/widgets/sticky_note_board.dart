import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../services/gamification_service.dart';
import '../services/reward_feedback_service.dart';
import '../settings_service.dart';
import '../sound_service.dart';
import '../thought_provider.dart';
import '../utils/title_generator.dart';
import '../utils/app_toast.dart';
import '../utils/global_error_handler.dart';
import 'sticky_note_bucket_picker.dart';

/// 8 Pastel post-it colors matching the design in Image 2
const List<Color> kStickyNoteColors = [
  Color(0xFFFDE68A), // 0: Warm Lemon Yellow
  Color(0xFFA7F3D0), // 1: Mint Green
  Color(0xFFFBCFE8), // 2: Pastel Pink
  Color(0xFFBAE6FD), // 3: Baby Sky Blue
  Color(0xFFFED7AA), // 4: Peach / Orange
  Color(0xFFDDD6FE), // 5: Lavender / Lilac
  Color(0xFFFEF3C7), // 6: Cream / Off-white
  Color(0xFFBBF7D0), // 7: Pale Sage
];

/// Subtle natural rotations (tilts) for sticky notes on the board (-1.4° to +1.4°)
/// anchored at Alignment.topCenter where the red pushpin is pinned
const List<double> kStickyNoteRotations = [
  -0.022, // Slot 0: ~ -1.26° (slight tilt left)
   0.018, // Slot 1: ~ +1.03° (slight tilt right)
  -0.012, // Slot 2: ~ -0.69° (very gentle tilt left)
   0.025, // Slot 3: ~ +1.43° (gentle tilt right)
   0.016, // Slot 4: ~ +0.92° (gentle tilt right)
  -0.024, // Slot 5: ~ -1.38° (gentle tilt left)
   0.014, // Slot 6: ~ +0.80° (gentle tilt right)
  -0.016, // Slot 7: ~ -0.92° (gentle tilt left)
];

class StickyNoteBoard extends StatefulWidget {
  final VoidCallback onOpenSorted;
  final bool isExpandedView;
  final VoidCallback? onToggleExpand;

  const StickyNoteBoard({
    super.key,
    required this.onOpenSorted,
    this.isExpandedView = false,
    this.onToggleExpand,
  });

  @override
  State<StickyNoteBoard> createState() => _StickyNoteBoardState();
}

class _StickyNoteBoardState extends State<StickyNoteBoard> {
  String? _selectedThoughtId;
  int _lastSecondaryTapTime = 0;
  String? _peelingThoughtId;
  int? _lastFreedSlotIndex;

  Color _getNoteColor(int index) {
    return kStickyNoteColors[index % kStickyNoteColors.length];
  }

  void _onBoardSecondaryTapDown(BuildContext context, TapDownDetails details) {
    // If a note was just right-clicked within 350ms, prevent the outer board from opening its menu
    if (DateTime.now().millisecondsSinceEpoch - _lastSecondaryTapTime < 350) {
      return;
    }
    _showBoardContextMenu(context, details.globalPosition);
  }

  void _showBoardContextMenu(BuildContext context, Offset globalPos) async {
    final provider = context.read<ThoughtProvider>();
    final unsortedCount = provider.unsortedCount;
    final isFull = provider.isBoardFull;

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF1E222B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF333B48)),
      ),
      items: [
        // Board Menu Header (clear distinction from Note Menu)
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Row(
            children: [
              const Icon(Icons.dashboard_outlined,
                  color: Color(0xFFFFD54F), size: 16),
              const SizedBox(width: 8),
              Text(
                'BOARD OPTIONS',
                style: appFont(
                  color: const Color(0xFFFFD54F),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'new',
          enabled: !isFull,
          child: Row(
            children: [
              const Icon(Icons.add, color: Color(0xFFFFD54F), size: 18),
              const SizedBox(width: 10),
              Text(
                'New sticky note',
                style: appFont(
                  color: isFull ? Colors.grey : const Color(0xFFFFD54F),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'pin_sorted',
          enabled: !isFull && provider.sortedCount > 0,
          child: Row(
            children: [
              const Icon(Icons.push_pin_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text(
                'Pin from Sorted',
                style: appFont(
                  color: (isFull || provider.sortedCount == 0)
                      ? Colors.grey
                      : Colors.white,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'pin_unsorted',
          enabled: !isFull && unsortedCount > 0,
          child: Row(
            children: [
              const Icon(Icons.push_pin_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text(
                'Pin from Unsorted ($unsortedCount)',
                style: appFont(
                  color: (isFull || unsortedCount == 0)
                      ? Colors.grey
                      : Colors.white,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;

    if (selected == 'new') {
      _showCreateStickyNoteDialog(context);
    } else if (selected == 'pin_sorted') {
      _showPinListPicker(context, isSorted: true);
    } else if (selected == 'pin_unsorted') {
      _showPinListPicker(context, isSorted: false);
    }
  }

  /// Right-click context menu specifically for a Sticky Note on the Board
  void _showNoteContextMenu(
      BuildContext context, Offset globalPos, Map<String, dynamic> thought,
      {Color? color}) async {
    _lastSecondaryTapTime = DateTime.now().millisecondsSinceEpoch;
    final provider = context.read<ThoughtProvider>();
    final settings = context.read<SettingsService>();
    final id = thought['id'] as String;
    final title = (thought['title'] as String?)?.isNotEmpty == true
        ? thought['title'] as String
        : 'Note';

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPos & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: const Color(0xFF1E222B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF333B48)),
      ),
      items: [
        // Note Menu Header with Note Title
        PopupMenuItem<String>(
          enabled: false,
          height: 34,
          child: Row(
            children: [
              Icon(Icons.push_pin,
                  color: color ?? const Color(0xFFFFD54F), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(
                    color: color ?? const Color(0xFFFFD54F),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: 'done',
          child: Row(
            children: [
              const Icon(Icons.check, color: Color(0xFFFFD54F), size: 18),
              const SizedBox(width: 10),
              Text('Mark done', style: appFont(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'split',
          child: Row(
            children: [
              const Icon(Icons.splitscreen, color: Color(0xFFFFD54F), size: 18),
              const SizedBox(width: 10),
              Text('Split into smaller tasks',
                  style: appFont(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text('Edit', style: appFont(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy_outlined, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text('Copy', style: appFont(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'move_bucket',
          child: Row(
            children: [
              const Icon(Icons.drive_file_move_outlined, color: Color(0xFFFFD54F), size: 18),
              const SizedBox(width: 10),
              Text('Move to bucket', style: appFont(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'unpin',
          child: Row(
            children: [
              const Icon(Icons.close, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Text('Remove from board (unpin)',
                  style: appFont(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'trash',
          child: Row(
            children: [
              const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
              const SizedBox(width: 10),
              Text('Delete to Trash',
                  style: appFont(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;

    switch (selected) {
      case 'done':
        setState(() => _peelingThoughtId = id);
        final reduce = settings.reduceAnimations || (MediaQuery.maybeOf(context)?.disableAnimations ?? false);
        await Future.delayed(Duration(milliseconds: reduce ? 0 : 260));
        final rootCtx = GlobalErrorHandler.navigatorKey.currentContext ?? context;
        debugPrint('[RewardFlow] board.markDone id=$id mounted=$mounted');
        final xp = await provider.markDone(id, true);
        debugPrint('[RewardFlow] board.markDone xp=$xp');
        final reward = GamificationService.instance.consumePendingRewardEvent();
        debugPrint('[RewardFlow] board.consume reward=${reward != null} xp=${reward?.xpEarned} coins=${reward?.coinsEarned} goal=${reward?.dailyGoalReached} levelUp=${reward?.leveledUp}');
        if (mounted) {
          setState(() {
            _peelingThoughtId = null;
            _lastFreedSlotIndex = 0;
          });
        }
        if (rootCtx.mounted) {
          RewardFeedbackService.showTaskReward(rootCtx, xp: xp, settings: settings);
          if (reward != null) {
            await RewardFeedbackService.maybeShowLevelUp(rootCtx, event: reward, settings: settings);
            await RewardFeedbackService.maybeShowDailyGoal(rootCtx, game: GamificationService.instance, settings: settings);
          } else {
            await RewardFeedbackService.maybeShowDailyGoal(rootCtx, game: GamificationService.instance, settings: settings);
          }
        } else {
          debugPrint('[RewardFlow] board early-return: rootCtx not mounted');
        }
        break;
      case 'split':
        _showSplitDialog(context, thought);
        break;
      case 'edit':
        _showEditDialog(context, thought);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: thought['content']?.toString() ?? ''));
        if (mounted) {
          AppToast.show(context, message: 'Copied "$title"');
        }
        break;
      case 'move_bucket':
        _showMoveToBucketDialog(context, thought);
        break;
      case 'unpin':
        await provider.unpinFromBoard(id);
        if (mounted) {
          AppToast.show(
              context, message: 'Removed "$title" from board (kept in list)');
        }
        break;
      case 'trash':
        await provider.moveToTrash(id);
        SoundService.instance.play(SoundEvent.trash, settings: settings);
        if (mounted) {
          AppToast.show(context, message: 'Moved "$title" to trash');
        }
        break;
    }
  }

  void _showMoveToBucketDialog(BuildContext context, Map<String, dynamic> thought) {
    final provider = context.read<ThoughtProvider>();
    final currentBucket = (thought['bucket'] ?? '').toString().trim();
    final buckets = provider.bucketNames.toList();
    for (final required in ['Raw', 'Main', 'Sides']) {
      if (!buckets.any((b) => b.toLowerCase() == required.toLowerCase())) {
        buckets.insert(0, required);
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        String selected = buckets.isNotEmpty ? buckets.first : 'Raw';
        if (currentBucket.isNotEmpty &&
            buckets.any((b) => b.toLowerCase() == currentBucket.toLowerCase())) {
          selected = buckets.firstWhere(
              (b) => b.toLowerCase() == currentBucket.toLowerCase());
        }
        final newBucketCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            backgroundColor: const Color(0xFF1E222B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF333B48)),
            ),
            title: Text(
              'Move to bucket',
              style: appFont(
                  color: const Color(0xFFFFD54F),
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: buckets.map((name) {
                      final isSelected =
                          name.toLowerCase() == selected.toLowerCase();
                      return ChoiceChip(
                        label: Text(name),
                        selected: isSelected,
                        selectedColor: const Color(0xFFFFD54F),
                        labelStyle: appFont(
                          color: isSelected ? Colors.black : Colors.white,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                        backgroundColor: const Color(0xFF262C38),
                        onSelected: (_) => setState(() => selected = name),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newBucketCtrl,
                    style: appFont(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Or create new bucket',
                      labelStyle: appFont(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFF333B48)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: appFont(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD54F),
                  foregroundColor: Colors.black,
                ),
                onPressed: () async {
                  final typed = newBucketCtrl.text.trim();
                  final target = typed.isNotEmpty ? typed : selected;
                  Navigator.pop(ctx);
                  await provider.moveToBucket(thought['id'] as String, target);
                  if (mounted) {
                    AppToast.show(context, message: 'Moved to "$target"');
                  }
                },
                child: const Text('Move'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreateStickyNoteDialog(BuildContext context,
      {String initialBucket = 'Raw'}) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String selectedBucket = initialBucket;
    DateTime? optionalDue;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E222B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF333B48)),
          ),
          title: Text(
            selectedBucket.toLowerCase() == 'main'
                ? 'New Main task'
                : 'New Sticky Note',
            style: appFont(
              color: const Color(0xFFFFD54F),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  style: appFont(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: appFont(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF333B48)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 3,
                  style: appFont(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Thought text',
                    labelStyle: appFont(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF333B48)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                StickyNoteBucketPicker(
                  initialBucket: initialBucket,
                  onBucketChanged: (val) {
                    setDialogState(() => selectedBucket = val);
                  },
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFFD54F),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    icon: const Icon(Icons.event_outlined, size: 16),
                    label: Text(
                      optionalDue == null
                          ? 'Optional date'
                          : 'Date: ${optionalDue!.year}-${optionalDue!.month.toString().padLeft(2, '0')}-${optionalDue!.day.toString().padLeft(2, '0')}',
                      style: appFont(fontSize: 12),
                    ),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: optionalDue ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => optionalDue = picked);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: appFont(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                final text = contentCtrl.text.trim();
                final title = titleCtrl.text.trim();
                if (text.isEmpty && title.isEmpty) return;

                Navigator.pop(ctx);
                final provider = context.read<ThoughtProvider>();
                final bucket = selectedBucket.trim().isNotEmpty ? selectedBucket.trim() : 'Raw';
                await provider.addBucket(bucket);
                final thought = await provider.addThought(
                  text.isNotEmpty ? text : title,
                  'thought',
                  bucket: bucket,
                  dueAt: optionalDue?.millisecondsSinceEpoch,
                );
                if (title.isNotEmpty) {
                  await provider.updateThoughtTitle(thought['id'], title,
                      titleSource: 'user');
                }
                if (bucket.toLowerCase() != 'main') {
                  await provider.pinToBoard(thought['id']);
                }
              },
              child: Text(selectedBucket.toLowerCase() == 'main'
                  ? 'Add to Main'
                  : 'Pin to Board'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddMenuOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return ListTile(
      enabled: enabled,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFFFD54F).withValues(alpha: 0.12) : const Color(0xFF262C38),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: enabled ? const Color(0xFFFFD54F) : Colors.grey,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: appFont(
          color: enabled ? Colors.white : Colors.grey,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: appFont(
          color: enabled ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563),
          fontSize: 12,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: enabled ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563),
        size: 18,
      ),
      onTap: enabled ? onTap : null,
    );
  }

  /// Add menu bottom sheet for phone (Requirement 2)
  void _showAddBoardBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E222B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF333B48)),
      ),
      builder: (ctx) {
        final provider = context.watch<ThoughtProvider>();
        final isFull = provider.isBoardFull;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4B5563),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ADD TO BOARD',
                        style: appFont(
                          color: const Color(0xFFFFD54F),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        '${provider.pinnedCount}/${ThoughtProvider.maxBoardPins} pinned',
                        style: appFont(
                          color: isFull ? Colors.amberAccent : const Color(0xFF9CA3AF),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Divider(color: Color(0xFF333B48), height: 1),
                const SizedBox(height: 6),
                _buildAddMenuOption(
                  icon: Icons.note_add_outlined,
                  title: 'New sticky note',
                  subtitle: isFull ? 'Board is full (${ThoughtProvider.maxBoardPins}/${ThoughtProvider.maxBoardPins}). Swap a note to add' : 'Create a fresh thought on the board',
                  enabled: !isFull,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCreateStickyNoteDialog(context);
                  },
                ),
                _buildAddMenuOption(
                  icon: Icons.sort,
                  title: 'Pin from Sorted',
                  subtitle: 'Pick from your organized ideas',
                  enabled: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showPinListPicker(context, isSorted: true);
                  },
                ),
                _buildAddMenuOption(
                  icon: Icons.inbox_outlined,
                  title: 'Pin from Unsorted',
                  subtitle: '${provider.unsortedCount} thoughts in inbox',
                  enabled: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showPinListPicker(context, isSorted: false);
                  },
                ),
                _buildAddMenuOption(
                  icon: Icons.folder_open_outlined,
                  title: "Pin a bucket's top task",
                  subtitle: 'Select from ${provider.buckets.length} buckets',
                  enabled: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showPinBucketTopTaskPicker(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPinListPicker(BuildContext context, {required bool isSorted}) {
    final provider = context.read<ThoughtProvider>();
    final searchCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isFull = provider.isBoardFull;
          final allThoughts = isSorted
              ? provider.sortedThoughts.where((t) => !provider.isPinned(t)).toList()
              : provider.unsortedThoughts.where((t) => !provider.isPinned(t)).toList();

          final query = searchCtrl.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? allThoughts
              : allThoughts.where((t) {
                  final title = (t['title'] as String? ?? '').toLowerCase();
                  final content = (t['content'] as String? ?? '').toLowerCase();
                  final bucket = (t['bucket'] as String? ?? '').toLowerCase();
                  return title.contains(query) || content.contains(query) || bucket.contains(query);
                }).toList();

          return AlertDialog(
            backgroundColor: const Color(0xFF1E222B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF333B48)),
            ),
            title: Text(
              isSorted ? 'Pin from Sorted' : 'Pin from Unsorted',
              style: appFont(
                color: const Color(0xFFFFD54F),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            content: SizedBox(
              width: 460,
              height: 440,
              child: Column(
                children: [
                  // Search Bar
                  TextField(
                    controller: searchCtrl,
                    onChanged: (_) => setDialogState(() {}),
                    style: appFont(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search ideas...',
                      hintStyle: appFont(color: Colors.grey, fontSize: 13),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFFFFD54F), size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFF13151D),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF333B48)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Board Full Warning & Swap explanation
                  if (isFull)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFFFFD54F), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Board is full (${ThoughtProvider.maxBoardPins}/${ThoughtProvider.maxBoardPins}). Tap "Swap" to replace a note on the board.',
                              style: appFont(color: const Color(0xFFFFD54F), fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Thoughts list
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              query.isEmpty ? 'No available thoughts to pin' : 'No matching thoughts found',
                              style: appFont(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const Divider(color: Color(0xFF333B48), height: 1),
                            itemBuilder: (context, index) {
                              final t = filtered[index];
                              final title = (t['title'] as String?)?.isNotEmpty == true
                                  ? t['title'] as String
                                  : (t['content'] as String? ?? 'Untitled');
                              final bucket = t['bucket'] as String? ?? 'Unsorted';

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                title: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: appFont(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: Text(
                                  bucket,
                                  style: appFont(color: Colors.grey, fontSize: 11),
                                ),
                                trailing: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isFull ? const Color(0xFF262C38) : const Color(0xFFFFD54F),
                                    foregroundColor: isFull ? const Color(0xFFFFD54F) : Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: isFull ? const BorderSide(color: Color(0xFFFFD54F)) : BorderSide.none,
                                    ),
                                  ),
                                  onPressed: () async {
                                    if (isFull) {
                                      Navigator.pop(ctx);
                                      _showSwapDialog(context, t);
                                    } else {
                                      Navigator.pop(ctx);
                                      final ok = await provider.pinToBoard(t['id']);
                                      if (ok && mounted) {
                                        AppToast.show(context, message: 'Pinned "$title" to board');
                                      }
                                    }
                                  },
                                  child: Text(
                                    isFull ? 'Swap' : 'Pin',
                                    style: appFont(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Close', style: appFont(color: Colors.grey)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Swap candidate thought with an existing board note when board is full (Requirement 2)
  void _showSwapDialog(BuildContext context, Map<String, dynamic> candidateThought) {
    final provider = context.read<ThoughtProvider>();
    final candidateTitle = (candidateThought['title'] as String?)?.isNotEmpty == true
        ? candidateThought['title'] as String
        : (candidateThought['content'] as String? ?? 'Untitled');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333B48)),
        ),
        title: Text(
          'Swap with a board note',
          style: appFont(
            color: const Color(0xFFFFD54F),
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        content: SizedBox(
          width: 440,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select which pinned note to replace with "$candidateTitle":',
                style: appFont(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: provider.pinnedThoughts.length,
                  separatorBuilder: (_, _) => const Divider(color: Color(0xFF333B48), height: 1),
                  itemBuilder: (context, i) {
                    final note = provider.pinnedThoughts[i];
                    final noteTitle = (note['title'] as String?)?.isNotEmpty == true
                        ? note['title'] as String
                        : (note['content'] as String? ?? 'Untitled');
                    final noteBucket = note['bucket'] as String? ?? 'Unsorted';

                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.push_pin, color: _getNoteColor(i), size: 18),
                      title: Text(
                        noteTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appFont(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text(noteBucket, style: appFont(color: Colors.grey, fontSize: 11)),
                      trailing: const Icon(Icons.swap_horiz, color: Color(0xFFFFD54F)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await provider.unpinFromBoard(note['id']);
                        await provider.pinToBoard(candidateThought['id'], position: i);
                        if (mounted) {
                          AppToast.show(context, message: 'Swapped "$noteTitle" with "$candidateTitle" on board');
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: appFont(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  /// Pin a bucket's top task (Requirement 2)
  void _showPinBucketTopTaskPicker(BuildContext context) {
    final provider = context.read<ThoughtProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333B48)),
        ),
        title: Text(
          "Pin a bucket's top task",
          style: appFont(
            color: const Color(0xFFFFD54F),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        content: SizedBox(
          width: 440,
          height: 380,
          child: provider.buckets.isEmpty
              ? Center(
                  child: Text(
                    'No buckets created yet',
                    style: appFont(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  itemCount: provider.buckets.length,
                  separatorBuilder: (_, _) => const Divider(color: Color(0xFF333B48), height: 1),
                  itemBuilder: (context, i) {
                    final b = provider.buckets[i];
                    final bName = b['name'] as String;
                    final bucketThoughts = provider.getThoughtsForBucket(bName);
                    final topUnpinned = bucketThoughts.where((t) => !provider.isPinned(t)).toList();
                    final topTask = topUnpinned.isNotEmpty ? topUnpinned.first : null;
                    final topTitle = topTask != null
                        ? ((topTask['title'] as String?)?.isNotEmpty == true
                            ? topTask['title'] as String
                            : (topTask['content'] as String? ?? 'Untitled'))
                        : 'No unpinned tasks';

                    final isFull = provider.isBoardFull;

                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder_outlined, color: Color(0xFFFFD54F), size: 20),
                      title: Text(
                        bName,
                        style: appFont(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text(
                        'Top task: $topTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appFont(color: topTask != null ? const Color(0xFF9CA3AF) : Colors.grey, fontSize: 11),
                      ),
                      trailing: topTask == null
                          ? null
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isFull ? const Color(0xFF262C38) : const Color(0xFFFFD54F),
                                foregroundColor: isFull ? const Color(0xFFFFD54F) : Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: isFull ? const BorderSide(color: Color(0xFFFFD54F)) : BorderSide.none,
                                ),
                              ),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                if (isFull) {
                                  _showSwapDialog(context, topTask);
                                } else {
                                  final ok = await provider.pinToBoard(topTask['id']);
                                  if (ok && mounted) {
                                    AppToast.show(context, message: 'Pinned "$topTitle" from $bName');
                                  }
                                }
                              },
                              child: Text(
                                isFull ? 'Swap' : 'Pin',
                                style: appFont(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: appFont(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  /// Profile and Daily Goal modal sheet (Requirement 5)
  void _showDailyGoalProfileSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E222B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF333B48)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final gamification = context.watch<GamificationService>();
          final done = gamification.todayCompletedCount;
          final goal = gamification.currentGoal;
          final progress = (done / math.max(goal, 1)).clamp(0.0, 1.0);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4B5563),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header with Level, Coins & Streak
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFD54F),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'LEVEL ${gamification.level}',
                              style: appFont(
                                color: Colors.black,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF13151D),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF333B48)),
                            ),
                            child: Text(
                              '${gamification.coinBalance} coins',
                              style: appFont(
                                color: const Color(0xFFFFD54F),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF13151D),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF333B48)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department, color: Color(0xFFFF8A65), size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${gamification.streak} day streak',
                              style: appFont(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${gamification.totalXp} XP total',
                    style: appFont(color: const Color(0xFF9CA3AF), fontSize: 12),
                  ),

                  const SizedBox(height: 16),

                  // Level Progress Bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Level progress',
                            style: appFont(color: const Color(0xFF9CA3AF), fontSize: 12),
                          ),
                          Text(
                            '${gamification.currentLevelXp} / ${gamification.nextLevelTargetXp} XP',
                            style: appFont(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: gamification.levelProgress,
                          minHeight: 8,
                          backgroundColor: const Color(0xFF13151D),
                          color: const Color(0xFFFFD54F),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Today's Goal Ring & Status Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13151D),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF333B48)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 5,
                                backgroundColor: const Color(0xFF262C38),
                                color: const Color(0xFFFFD54F),
                              ),
                              Text(
                                '$done/$goal',
                                style: appFont(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                gamification.isDailyGoalReached
                                    ? 'Daily goal reached! 🎉 (+10 Bonus XP)'
                                    : 'Daily goal: finish $goal pinned tasks',
                                style: appFont(
                                  color: gamification.isDailyGoalReached ? const Color(0xFFFFD54F) : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Only tasks marked done from pinned board notes count.',
                                style: appFont(color: const Color(0xFF9CA3AF), fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '1 rest day per week protects your streak.',
                                style: appFont(color: const Color(0xFF6B7280), fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Effort Rewards Guide
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13151D),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _xpGuidePill('Quick', '+5 XP'),
                        _xpGuidePill('Medium', '+10 XP'),
                        _xpGuidePill('Big', '+20 XP'),
                        _xpGuidePill('Goal bonus', '+10 XP'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Goal Settings (Lower or Fix Goal)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily goal target',
                            style: appFont(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Text(
                            gamification.isGoalFixed ? 'Fixed goal' : 'Auto-increases every 5-day streak',
                            style: appFont(color: const Color(0xFF9CA3AF), fontSize: 11),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFFFD54F), size: 22),
                            onPressed: goal > 1
                                ? () => gamification.setGoalSettings(
                                      isFixed: true,
                                      goalValue: goal - 1,
                                    )
                                : null,
                          ),
                          Text(
                            '$goal',
                            style: appFont(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Color(0xFFFFD54F), size: 22),
                            onPressed: goal < 20
                                ? () => gamification.setGoalSettings(
                                      isFixed: true,
                                      goalValue: goal + 1,
                                    )
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Unlocks', style: appFont(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  ...GamificationService.levelRewards.map((r) {
                    final unlocked = gamification.level >= r.level;
                    final owned = gamification.isUnlockOwned(r.name);
                    final canUse = unlocked && owned;
                    final selected = (r.type == 'cosmetic_title' && gamification.selectedTitle == r.name) ||
                        (r.type == 'note_color' && gamification.selectedNoteColor == r.name) ||
                        (r.type == 'pin_style' && gamification.selectedPinStyle == r.name);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF13151D), borderRadius: BorderRadius.circular(10), border: Border.all(color: selected ? const Color(0xFFFFD54F) : const Color(0xFF333B48))),
                      child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('L${r.level} ${r.name}', style: appFont(color: unlocked ? Colors.white : Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                          Text(r.description, style: appFont(color: const Color(0xFF9CA3AF), fontSize: 11)),
                        ])),
                        if (canUse)
                          TextButton(onPressed: selected ? null : () => gamification.selectUnlock(r.name), child: Text(selected ? 'Using' : 'Use', style: appFont(color: const Color(0xFFFFD54F), fontSize: 12)))
                        else
                          Text(unlocked ? 'Owned' : 'Locked', style: appFont(color: const Color(0xFF9CA3AF), fontSize: 12)),
                      ]),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _xpGuidePill(String label, String xp) {
    return Column(
      children: [
        Text(xp, style: appFont(color: const Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 2),
        Text(label, style: appFont(color: const Color(0xFF9CA3AF), fontSize: 10)),
      ],
    );
  }

  void _showSplitDialog(BuildContext context, Map<String, dynamic> thought) {
    final provider = context.read<ThoughtProvider>();
    final content = thought['content'] as String? ?? '';
    final title = thought['title'] as String? ?? '';
    final bucket = thought['bucket'] as String? ?? 'General';
    final initialText = content.trim().isNotEmpty ? content.trim() : title.trim();
    final ctrl = TextEditingController(text: initialText);
    bool keepOriginal = true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333B48)),
        ),
        title: Row(
          children: [
            const Icon(Icons.splitscreen, color: Color(0xFFFFD54F), size: 22),
            const SizedBox(width: 8),
            Text(
              'Split into Smaller Tasks',
              style: appFont(
                color: Colors.white,
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
                'Original thought: "${title.isNotEmpty ? title : content}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: appFont(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                'Enter each new task on a separate line:',
                style: appFont(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 5,
                autofocus: true,
                style: appFont(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Task 1\nTask 2\nTask 3',
                  hintStyle: appFont(color: Colors.grey.withValues(alpha: 0.5)),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFF333B48)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              StatefulBuilder(
                builder: (context, setDialogState) {
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF14171F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2E3544)),
                    ),
                    child: CheckboxListTile(
                      value: keepOriginal,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      activeColor: const Color(0xFFFFD54F),
                      checkColor: Colors.black,
                      title: Text(
                        'Keep original note in "$bucket"',
                        style: appFont(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        keepOriginal
                            ? 'Original note remains safely in bucket (unpinned from board)'
                            : 'Original note will be moved to Trash once split',
                        style: appFont(color: Colors.grey, fontSize: 11),
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
            child: Text('Cancel', style: appFont(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD54F),
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
              final result = await provider.splitThought(thought['id'], lines,
                  keepOriginal: keepOriginal);

              if (mounted) {
                final originalMsg = keepOriginal
                    ? 'Original note kept in "$bucket".'
                    : 'Original note moved to Trash.';
                final fullMsg = result.pinnedCount < result.createdCount
                    ? 'Created ${result.createdCount} tasks in "$bucket". Pinned ${result.pinnedCount}; remaining tasks kept in bucket (board full ${ThoughtProvider.maxBoardPins}/${ThoughtProvider.maxBoardPins}). $originalMsg'
                    : 'Created and pinned ${result.createdCount} tasks in "$bucket". $originalMsg';

                AppToast.show(
                  context,
                  message: fullMsg,
                  actionLabel: !keepOriginal ? 'UNDO' : null,
                  onAction: !keepOriginal
                      ? () async {
                          await provider.restoreFromTrash(thought['id']);
                          await provider.loadThoughts();
                        }
                      : null,
                );
              }
            },
            child: const Text('Split & Pin'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, Map<String, dynamic> thought) {
    final provider = context.read<ThoughtProvider>();
    final titleCtrl = TextEditingController(text: thought['title'] ?? '');
    final contentCtrl = TextEditingController(text: thought['content'] ?? '');
    final currentBucket = thought['bucket']?.toString().trim();
    String selectedBucket = (currentBucket != null && currentBucket.isNotEmpty)
        ? currentBucket
        : 'Raw';
    final rawDue = thought['due_at'];
    DateTime? dueDate = rawDue is num
        ? DateTime.fromMillisecondsSinceEpoch(rawDue.toInt())
        : null;
    String recurrence =
        (thought['recurrence'] as String?)?.trim().toLowerCase() ?? '';
    if (recurrence.isEmpty &&
        (selectedBucket.toLowerCase() == 'main' ||
            selectedBucket.toLowerCase() == 'sides')) {
      recurrence = 'daily';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E222B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF333B48)),
          ),
          title: Text(
            'Edit Sticky Note',
            style: appFont(
              color: const Color(0xFFFFD54F),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  style: appFont(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Title',
                    labelStyle: appFont(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF333B48)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contentCtrl,
                  maxLines: 4,
                  style: appFont(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Content',
                    labelStyle: appFont(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF333B48)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                StickyNoteBucketPicker(
                  initialBucket: selectedBucket,
                  onBucketChanged: (val) {
                    setDialogState(() => selectedBucket = val);
                  },
                ),
                if (selectedBucket.toLowerCase() == 'raw') ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFFD54F),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          icon: const Icon(Icons.event_outlined, size: 16),
                          label: Text(
                            dueDate == null
                                ? 'Optional date'
                                : 'Date: ${dueDate!.year}-${dueDate!.month.toString().padLeft(2, '0')}-${dueDate!.day.toString().padLeft(2, '0')}',
                            style: appFont(fontSize: 12),
                          ),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: dueDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() => dueDate = picked);
                            }
                          },
                        ),
                      ),
                      if (dueDate != null)
                        IconButton(
                          tooltip: 'Clear date',
                          icon: const Icon(Icons.close, size: 16),
                          color: Colors.grey,
                          onPressed: () => setDialogState(() => dueDate = null),
                        ),
                    ],
                  ),
                ],
                if (selectedBucket.toLowerCase() == 'main' ||
                    selectedBucket.toLowerCase() == 'sides') ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Repeats',
                      style: appFont(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final option in const ['daily', 'weekly', 'none'])
                        ChoiceChip(
                          label: Text(
                            option == 'daily'
                                ? 'Daily'
                                : option == 'weekly'
                                    ? 'Weekly'
                                    : 'None',
                          ),
                          selected: (recurrence.isEmpty ? 'none' : recurrence) ==
                              option,
                          selectedColor: const Color(0xFFFFD54F),
                          backgroundColor: const Color(0xFF262C38),
                          labelStyle: appFont(
                            color: (recurrence.isEmpty ? 'none' : recurrence) ==
                                    option
                                ? Colors.black
                                : Colors.white,
                            fontSize: 12,
                          ),
                          onSelected: (_) => setDialogState(
                              () => recurrence = option == 'none' ? '' : option),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: appFont(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD54F),
                foregroundColor: Colors.black,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                final bucket = selectedBucket.trim().isNotEmpty ? selectedBucket.trim() : 'Raw';
                final isMainOrSides = bucket.toLowerCase() == 'main' ||
                    bucket.toLowerCase() == 'sides';
                await provider.addBucket(bucket);
                await provider.fileThought(thought['id'], bucket);
                await provider.updateThoughtTitle(thought['id'], titleCtrl.text.trim(),
                    titleSource: 'user');
                await provider.updateContent(thought['id'], contentCtrl.text.trim());
                await provider.setDueDate(
                    thought['id'], bucket.toLowerCase() == 'raw' ? dueDate : null);
                await provider.setRecurrence(
                    thought['id'],
                    isMainOrSides
                        ? (recurrence.isEmpty ? 'none' : recurrence)
                        : null);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyGoalRing(BuildContext context) {
    final gamification = context.watch<GamificationService>();
    final done = gamification.todayCompletedCount;
    final goal = gamification.currentGoal;
    final progress = (done / math.max(goal, 1)).clamp(0.0, 1.0);

    return InkWell(
      onTap: () => _showDailyGoalProfileSheet(context),
      borderRadius: BorderRadius.circular(20),
      child: Tooltip(
        message: 'Daily Goal: $done/$goal completed. Tap for profile & XP',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF1E222B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: gamification.isDailyGoalReached
                  ? const Color(0xFFFFD54F)
                  : const Color(0xFF333B48),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 2.5,
                      backgroundColor: const Color(0xFF333B48),
                      color: const Color(0xFFFFD54F),
                    ),
                    if (gamification.isDailyGoalReached)
                      const Icon(Icons.check, size: 12, color: Color(0xFFFFD54F)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$done/$goal',
                style: appFont(
                  color: gamification.isDailyGoalReached
                      ? const Color(0xFFFFD54F)
                      : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThoughtProvider>();
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final pinned = provider.pinnedThoughts;
    final pinnedCount = pinned.length;

    // QUARTER-SCREEN PREVIEW MODE (When embedded at top of Stream)
    if (!widget.isExpandedView) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF13151D),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Preview Header
            Row(
              children: [
                const Icon(Icons.push_pin, color: Color(0xFFFFD54F), size: 16),
                const SizedBox(width: 8),
                Text(
                  'PINNED BOARD',
                  style: appFont(
                    color: const Color(0xFFFFD54F),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFFD54F).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '$pinnedCount / ${ThoughtProvider.maxBoardPins} pinned',
                    style: appFont(
                      color: const Color(0xFFFFD54F),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFFD54F),
                    side: const BorderSide(color: Color(0xFFFFD54F)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.fullscreen, size: 16),
                  label: Text('Expand Board',
                      style: appFont(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: widget.onToggleExpand,
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Horizontal scrolling row of large readable cards in quarter-screen mode
            Expanded(
              child: pinned.isEmpty
                  ? GestureDetector(
                      onTap: widget.onToggleExpand,
                      onSecondaryTapDown: (details) =>
                          _onBoardSecondaryTapDown(context, details),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFF262C38),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              '+ No pinned thoughts yet. Click "Pin to board" in any menu or right-click to add.',
                              textAlign: TextAlign.center,
                              style: appFont(
                                  color: colors.mute, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: pinned.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) {
                        final thought = pinned[i];
                        final color = _getNoteColor(i);
                        final rotationAngle =
                            kStickyNoteRotations[i % kStickyNoteRotations.length] *
                                0.7;
                        return SizedBox(
                          width: 180,
                          child: Transform.rotate(
                            angle: rotationAngle,
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () {
                                _showStickyNoteDetailPopup(
                                    context, thought, color);
                              },
                              onSecondaryTapDown: (details) => _showNoteContextMenu(
                                  context, details.globalPosition, thought,
                                  color: color),
                              child: _buildStickyNoteCard(
                                thought: thought,
                                color: color,
                                isSelected: false,
                                cellWidth: 180,
                                cellHeight: 110,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    }

    // FULLSCREEN 4×2 GRID VIEW MATCHING IMAGE 2
    return GestureDetector(
      onSecondaryTapDown: (details) => _onBoardSecondaryTapDown(context, details),
      onTap: () {
        if (_selectedThoughtId != null) {
          setState(() => _selectedThoughtId = null);
        }
      },
      child: Container(
        color: const Color(0xFF13151D),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar: [Sort icon only] [BOARD] [daily-goal ring "2/4"] on ONE row (Requirement 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left: Sort icon only
                InkWell(
                  onTap: widget.onOpenSorted,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E222B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF333B48), width: 1.2),
                    ),
                    child: const Icon(Icons.sort, size: 20, color: Colors.white),
                  ),
                ),

                // Center Title: BOARD only
                Text(
                  'BOARD',
                  style: appFont(
                    color: const Color(0xFFFFD54F),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    fontSize: 16,
                  ),
                ),

                // Right: Daily-goal ring showing progress (e.g. "2/4")
                _buildDailyGoalRing(context),
              ],
            ),

            const SizedBox(height: 14),

            // Sticky Note grid: slot 0 is the reserved Main card, then up to 7 pins
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isNarrow = constraints.maxWidth < 650;
                  final crossAxisCount = isNarrow ? 2 : 4;
                  final rowCount = isNarrow ? 4 : 2;
                  const spacing = 12.0;

                  final cellWidth = (constraints.maxWidth -
                          (crossAxisCount - 1) * spacing) /
                      crossAxisCount;
                  final cellHeight = (constraints.maxHeight -
                          (rowCount - 1) * spacing) /
                      rowCount;

                  final childAspectRatio = cellWidth / math.max(cellHeight, 1);

                  return GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: childAspectRatio > 0 ? childAspectRatio : 1.3,
                    ),
                    itemCount: 1 + ThoughtProvider.maxBoardPins,
                    itemBuilder: (context, slotIndex) {
                      if (slotIndex == 0) {
                        return _buildMainBoardCard(
                          context: context,
                          cellWidth: cellWidth,
                          cellHeight: cellHeight,
                        );
                      }

                      final pinIndex = slotIndex - 1;

                      if (pinIndex < pinnedCount) {
                        final thought = pinned[pinIndex];
                        final isSelected = thought['id'] == _selectedThoughtId;
                        final color = _getNoteColor(pinIndex);
                        final rotationAngle =
                            kStickyNoteRotations[pinIndex % kStickyNoteRotations.length];

                        return DragTarget<int>(
                          onAcceptWithDetails: (details) {
                            final fromIndex = details.data;
                            if (fromIndex != pinIndex) {
                              provider.reorderBoard(fromIndex, pinIndex);
                            }
                          },
                          builder: (context, candidateData, rejectedData) {
                            return Transform.rotate(
                              angle: rotationAngle,
                              alignment: Alignment.topCenter,
                              child: GestureDetector(
                                onTap: () {
                                  _showStickyNoteDetailPopup(
                                      context, thought, color);
                                },
                                onLongPress: () {
                                  _showAddBoardBottomSheet(context);
                                },
                                onSecondaryTapDown: (details) =>
                                    _showNoteContextMenu(
                                        context, details.globalPosition, thought,
                                        color: color),
                                child: _buildStickyNoteCard(
                                  thought: thought,
                                  color: color,
                                  isSelected: isSelected,
                                  cellWidth: cellWidth,
                                  cellHeight: cellHeight,
                                  slotIndex: pinIndex,
                                  rotationAngle: rotationAngle,
                                ),
                              ),
                            );
                          },
                        );
                      } else {
                        // Empty Slots (one "+" slot, other slots faint outlines)
                        final isSingleAddSlot = pinIndex == pinnedCount;

                        // Check if we should suggest next best task from Sorted to pin into an emptied slot (Requirement 5)
                        final nextBest = (_lastFreedSlotIndex != null && isSingleAddSlot)
                            ? provider.bestNextUnpinnedThought
                            : null;

                        if (nextBest != null) {
                          final nextTitle = (nextBest['title'] as String?)?.isNotEmpty == true
                              ? nextBest['title'] as String
                              : (nextBest['content'] as String? ?? 'Next idea');

                          return GestureDetector(
                            onTap: () async {
                              final ok = await provider.pinToBoard(nextBest['id'], position: pinIndex);
                              if (ok && mounted) {
                                AppToast.show(context, message: 'Pinned "$nextTitle"');
                                setState(() => _lastFreedSlotIndex = null);
                              }
                            },
                            onSecondaryTapDown: (details) =>
                                _onBoardSecondaryTapDown(context, details),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF161A23),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFFFD54F).withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.auto_awesome, color: Color(0xFFFFD54F), size: 18),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Pin next best:',
                                    style: appFont(color: const Color(0xFFFFD54F), fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    nextTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: appFont(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        if (isSingleAddSlot) {
                          // The ONE empty "+" slot (no text!)
                          return GestureDetector(
                            onTap: () => _showAddBoardBottomSheet(context),
                            onLongPress: () => _showAddBoardBottomSheet(context),
                            onSecondaryTapDown: (details) =>
                                _onBoardSecondaryTapDown(context, details),
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF161A23),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF333B48),
                                  width: 1.5,
                                ),
                              ),
                              child: const Center(
                                child: Icon(Icons.add, size: 26, color: Color(0xFF6B7280)),
                              ),
                            ),
                          );
                        } else {
                          // Other empty slots are just faint outlines (Requirement 1)
                          return GestureDetector(
                            onTap: () => _showAddBoardBottomSheet(context),
                            onLongPress: () => _showAddBoardBottomSheet(context),
                            onSecondaryTapDown: (details) =>
                                _onBoardSecondaryTapDown(context, details),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF1E222B),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          );
                        }
                      }
                    },
                  );
                },
              ),
            ),

            // Show pinned count as small text under the board ONLY if the board is full (Requirement 1)
            if (pinnedCount >= ThoughtProvider.maxBoardPins) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Board is full (${ThoughtProvider.maxBoardPins}/${ThoughtProvider.maxBoardPins}). Remove a note from the board first to add more.',
                  style: appFont(
                    color: const Color(0xFF9CA3AF),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 8),

            // Small Sort Button at the bottom (Requirement: "small sort at the bottom")
            Center(
              child: InkWell(
                onTap: widget.onOpenSorted,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF333B48)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.menu, size: 14, color: Color(0xFFFFD54F)),
                      const SizedBox(width: 8),
                      Text(
                        'Sort: View all thoughts (${provider.sortedCount} sorted, ${provider.unsortedCount} unsorted)',
                        style: appFont(
                          color: const Color(0xFFFFD54F),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
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

  Widget _buildMainBoardCard({
    required BuildContext context,
    required double cellWidth,
    required double cellHeight,
  }) {
    final provider = context.watch<ThoughtProvider>();
    final config = context.watch<SettingsService>();
    final current = provider.getMainPinThought();
    final total = provider.mainThoughts.length;
    final done = provider.mainCompletedCount;
    final allDone = provider.isAllMainDone;
    final progress = total == 0 ? 0.0 : done / total;

    return GestureDetector(
      onLongPress: () => _showMainPinOptions(context),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF232936), Color(0xFF171B24)],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFFFD54F).withValues(alpha: 0.55),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(2, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Color(0xFFFFD54F), size: 15),
                const SizedBox(width: 4),
                Text(
                  'MAIN',
                  style: appFont(
                    color: const Color(0xFFFFD54F),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                Text(
                  '$done/$total',
                  style: appFont(
                    color: Colors.grey.shade400,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: const Color(0xFF333B48),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD54F)),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: allDone
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Color(0xFF4CAF50), size: 22),
                          const SizedBox(height: 2),
                          Text(
                            'Main complete',
                            style: appFont(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )
                  : current == null
                      ? Center(
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFFD54F),
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            onPressed: () => _showCreateStickyNoteDialog(context,
                                initialBucket: 'Main'),
                            icon: const Icon(Icons.add, size: 15),
                            label: Text(
                              'Add Main task',
                              style: appFont(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: () => _showStickyNoteDetailPopup(
                              context, current, const Color(0xFFFFF3C4)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (current['title'] as String?)?.isNotEmpty == true
                                    ? current['title'] as String
                                    : (current['content'] as String? ?? 'Untitled'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: appFont(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Expanded(
                                child: Text(
                                  current['content'] as String? ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: appFont(
                                    color: Colors.grey.shade400,
                                    fontSize: 9.5,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
            ),
            if (!allDone && current != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 24,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD54F),
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        onPressed: () async {
                          final id = current['id'] as String;
                          final xp = await provider.markDone(id, true);
                          SoundService.instance.play(SoundEvent.save, settings: config);
                          if (context.mounted) {
                            final summary = GamificationService.instance.getSummaryString();
                            AppToast.show(
                              context,
                              message: xp > 0
                                  ? 'Main done! +$xp XP ($summary)'
                                  : 'Main task marked done',
                            );
                          }
                        },
                        child: Text(
                          'Done',
                          style: appFont(fontSize: 10, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 26,
                    height: 24,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      tooltip: 'Reshuffle Main',
                      icon: const Icon(Icons.shuffle, color: Color(0xFFFFD54F)),
                      onPressed: () async {
                        await provider.reshuffleMainPin();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMainPinOptions(BuildContext context) {
    final provider = context.read<ThoughtProvider>();
    final settings = context.read<SettingsService>();
    final mains = provider.mainThoughts;
    final currentId = settings.chosenMainPinId;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1E222B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF333B48)),
          ),
          title: Text(
            'Main card',
            style: appFont(
              color: const Color(0xFFFFD54F),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shuffle, color: Color(0xFFFFD54F)),
                  title: Text('Shuffle daily',
                      style: appFont(color: Colors.white, fontSize: 14)),
                  subtitle: Text('Pick a different Main task each day',
                      style: appFont(color: Colors.grey, fontSize: 12)),
                  trailing: settings.mainPinMode == 'shuffle'
                      ? const Icon(Icons.check, color: Color(0xFFFFD54F))
                      : null,
                  onTap: () async {
                    await settings.setMainPinMode('shuffle');
                    setState(() {});
                  },
                ),
                const Divider(color: Color(0xFF333B48)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.touch_app, color: Color(0xFFFFD54F)),
                  title: Text('Choose a task',
                      style: appFont(color: Colors.white, fontSize: 14)),
                  subtitle: Text('Keep one specific Main task pinned',
                      style: appFont(color: Colors.grey, fontSize: 12)),
                  trailing: settings.mainPinMode == 'choose'
                      ? const Icon(Icons.check, color: Color(0xFFFFD54F))
                      : null,
                  onTap: () async {
                    await settings.setMainPinMode('choose');
                    setState(() {});
                  },
                ),
                if (settings.mainPinMode == 'choose') ...[
                  const SizedBox(height: 8),
                  if (mains.isEmpty)
                    Text('No Main tasks yet.',
                        style: appFont(color: Colors.grey, fontSize: 12))
                  else
                    ...mains.map((t) {
                      final id = t['id'] as String;
                      final isDone = (t['done'] as num?)?.toInt() == 1 ||
                          t['status'] == 'completed';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          currentId == id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: currentId == id
                              ? const Color(0xFFFFD54F)
                              : Colors.grey,
                          size: 20,
                        ),
                        title: Text(
                          (t['title'] as String?)?.isNotEmpty == true
                              ? t['title'] as String
                              : (t['content'] as String? ?? 'Untitled'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: appFont(
                            color: isDone ? Colors.grey : Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        onTap: () async {
                          await settings.setChosenMainPinId(id);
                          setState(() {});
                        },
                      );
                    }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: appFont(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStickyNoteCard({
    required Map<String, dynamic> thought,
    required Color color,
    required bool isSelected,
    required double cellWidth,
    required double cellHeight,
    int? slotIndex,
    double? rotationAngle,
  }) {
    final title = (thought['title'] as String?)?.isNotEmpty == true
        ? thought['title'] as String
        : (thought['content'] as String? ?? 'Untitled');
    final content = thought['content'] as String? ?? '';
    final bucket = (thought['bucket'] as String?)?.trim() ?? '';
    final whenVal = thought['when_val'] as String? ?? '';
    final timeVal = thought['time_val'] as String? ?? '';

    // Show effort only if NOT medium (Requirement 1)
    final timeLower = timeVal.toLowerCase().trim();
    final String? showEffort = (timeLower == 'quick' || timeLower == 'big' || timeLower == 'long') ? timeLower : null;

    // Show due-soon as a small red/amber dot (Requirement 1)
    final bool isDueSoon = whenVal.isNotEmpty && whenVal != 'Later' && whenVal != 'Soon';

    final isPeeling = thought['id'] == _peelingThoughtId;

    return AnimatedScale(
      scale: isPeeling ? 0.75 : 1.0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOut,
      child: AnimatedOpacity(
        opacity: isPeeling ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 260),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Main Note Body with Curved Post-it paper effect (less padding: 10, 14, 10, 8)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomRight,
                  colors: [
                    color,
                    Color.lerp(color, Colors.white, 0.12)!,
                  ],
                  stops: const [0.72, 1.0],
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(22), // Natural curved paper lift
                ),
                boxShadow: [
                  // Curled paper lift shadow at bottom-right
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isSelected ? 0.42 : 0.28),
                    blurRadius: isSelected ? 16 : 10,
                    offset: const Offset(4, 7),
                  ),
                  // Ambient soft contact shadow
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title (one line, bold dark text)
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(
                      color: const Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),

                  // Content Preview (max 3 lines)
                  Expanded(
                    child: Text(
                      content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: appFont(
                        color: const Color(0xFF334155),
                        fontSize: 11.5,
                        height: 1.25,
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Bottom Badges: Bucket pill on left, Effort/Due dot on right
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Bucket badge pill
                      if (bucket.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            bucket,
                            style: appFont(
                              color: const Color(0xFF1E293B),
                              fontWeight: FontWeight.bold,
                              fontSize: 9.5,
                            ),
                          ),
                        )
                      else
                        const SizedBox.shrink(),

                      // Due-soon dot & Effort tag (only if not medium)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isDueSoon)
                            Container(
                              width: 6,
                              height: 6,
                              margin: EdgeInsets.only(right: showEffort != null ? 4 : 0),
                              decoration: const BoxDecoration(
                                color: Color(0xFFE11D48),
                                shape: BoxShape.circle,
                              ),
                            ),
                          if (showEffort != null)
                            Text(
                              showEffort,
                              style: appFont(
                                color: const Color(0xFF475569),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

        // Subtle paper curl lift highlight at bottom-right corner
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                bottomRight: Radius.circular(22),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withValues(alpha: 0.0),
                  Colors.black.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.22),
                ],
              ),
            ),
          ),
        ),

        // Positioned 3D Red Pushpin at top center with drag handle for reordering (Requirement 2)
        Positioned(
          top: -8,
          left: 0,
          right: 0,
          child: Center(
            child: slotIndex != null
                ? LongPressDraggable<int>(
                    data: slotIndex,
                    feedback: Material(
                      color: Colors.transparent,
                      child: SizedBox(
                        width: cellWidth,
                        height: cellHeight,
                        child: Opacity(
                          opacity: 0.85,
                          child: Transform.rotate(
                            angle: rotationAngle ?? 0.0,
                            alignment: Alignment.topCenter,
                            child: _buildStickyNoteCard(
                              thought: thought,
                              color: color,
                              isSelected: false,
                              cellWidth: cellWidth,
                              cellHeight: cellHeight,
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      color: Colors.transparent,
                      child: _buildPushpinWidget(),
                    ),
                  )
                : _buildPushpinWidget(),
          ),
        ),

        // Action Bar Overlay when Note is Selected (Requirement 2)
        if (isSelected)
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: _buildActionBar(context, thought),
          ),
      ],
    ),
  ),
);
  }

  /// Expanded Sticky Note Popup / Modal Card (Requirement: "expand into view a bit above... popup on smaller screen")
  void _showStickyNoteDetailPopup(
      BuildContext context, Map<String, dynamic> thought, Color noteColor) {
    final provider = context.read<ThoughtProvider>();
    final settings = context.read<SettingsService>();
    final id = thought['id'] as String;
    final title = (thought['title'] as String?)?.isNotEmpty == true
        ? thought['title'] as String
        : (thought['content'] as String? ?? 'Untitled');
    final content = thought['content'] as String? ?? '';
    final bucket = (thought['bucket'] as String?)?.trim() ?? '';
    final whenVal = thought['when_val'] as String? ?? '';
    final timeVal = thought['time_val'] as String? ?? '';
    final rawCreated = thought['created_at'];
    final createdAtMs = (rawCreated as num?)?.toInt();
    final timestamp = IdeaFormatters.formatReadableTimestamp(createdAtMs);

    String tagLabel = '';
    if (whenVal.isNotEmpty && whenVal != 'Soon') {
      tagLabel = 'due $whenVal'.toLowerCase();
    } else if (timeVal.isNotEmpty) {
      tagLabel = timeVal.toLowerCase();
    } else {
      tagLabel = 'quick';
    }

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) {
        final screenWidth = MediaQuery.of(ctx).size.width;
        final screenHeight = MediaQuery.of(ctx).size.height;
        final dialogWidth = math.min(screenWidth * 0.9, 480.0);
        final dialogMaxHeight = math.min(screenHeight * 0.82, 540.0);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Center(
            child: SizedBox(
              width: dialogWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Main Expanded Note Card with curved paper styling
                  Container(
                    constraints: BoxConstraints(maxHeight: dialogMaxHeight),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomRight,
                        colors: [
                          noteColor,
                          Color.lerp(noteColor, Colors.white, 0.10)!,
                        ],
                        stops: const [0.75, 1.0],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(6),
                        topRight: Radius.circular(6),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(26),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(4, 10),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Row: Bucket pill, Effort/Due badge, Timestamp, and Close button
                        Row(
                          children: [
                            if (bucket.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  bucket,
                                  style: appFont(
                                    color: const Color(0xFF0F172A),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tagLabel,
                                style: appFont(
                                  color: const Color(0xFF334155),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (timestamp.isNotEmpty)
                              Text(
                                timestamp,
                                style: appFont(
                                  color: const Color(0xFF475569),
                                  fontSize: 11,
                                ),
                              ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => Navigator.pop(ctx),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Full Title (no truncation)
                        SelectableText(
                          title,
                          style: appFont(
                            color: const Color(0xFF0F172A),
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            height: 1.25,
                          ),
                        ),

                        // Content (scrollable if long)
                        if (content.isNotEmpty && content != title) ...[
                          const SizedBox(height: 10),
                          const Divider(
                            color: Color(0x22000000),
                            height: 1,
                            thickness: 1,
                          ),
                          const SizedBox(height: 10),
                          Flexible(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: SelectableText(
                                content,
                                style: appFont(
                                  color: const Color(0xFF334155),
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                        ],

                        const SizedBox(height: 14),

                        // Action Bar at the bottom of the expanded note
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E222B),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _popupActionBtn(
                                icon: Icons.check,
                                label: 'Done',
                                color: const Color(0xFFFFD54F),
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  setState(() => _peelingThoughtId = id);
                                  await Future.delayed(const Duration(milliseconds: 260));
                                  final rootCtx = GlobalErrorHandler.navigatorKey.currentContext ?? context;
                                  debugPrint('[RewardFlow] popup.markDone id=$id');
                                  final xp = await provider.markDone(id, true);
                                  final reward = GamificationService.instance.consumePendingRewardEvent();
                                  debugPrint('[RewardFlow] popup.consume reward=${reward != null}');
                                  if (mounted) {
                                    setState(() {
                                      _peelingThoughtId = null;
                                      _lastFreedSlotIndex = 0;
                                    });
                                  }
                                  if (rootCtx.mounted) {
                                    RewardFeedbackService.showTaskReward(rootCtx, xp: xp, settings: settings);
                                    if (reward != null) {
                                      await RewardFeedbackService.maybeShowLevelUp(rootCtx, event: reward, settings: settings);
                                    }
                                    await RewardFeedbackService.maybeShowDailyGoal(rootCtx, game: GamificationService.instance, settings: settings);
                                  }
                                },
                              ),
                              _popupActionBtn(
                                icon: Icons.splitscreen,
                                label: 'Split',
                                color: Colors.white,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _showSplitDialog(context, thought);
                                },
                              ),
                              _popupActionBtn(
                                icon: Icons.edit_outlined,
                                label: 'Edit',
                                color: Colors.white,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _showEditDialog(context, thought);
                                },
                              ),
                              _popupActionBtn(
                                icon: Icons.copy_outlined,
                                label: 'Copy',
                                color: Colors.white,
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  await Clipboard.setData(ClipboardData(text: thought['content']?.toString() ?? ''));
                                  if (mounted) {
                                    AppToast.show(context, message: 'Copied "$title"');
                                  }
                                },
                              ),
                              _popupActionBtn(
                                icon: Icons.close,
                                label: 'Unpin',
                                color: Colors.white70,
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  await provider.unpinFromBoard(id);
                                  if (mounted) {
                                    AppToast.show(context,
                                        message:
                                            'Removed "$title" from board (kept in list)');
                                  }
                                },
                              ),
                              _popupActionBtn(
                                icon: Icons.delete_outline,
                                label: 'Trash',
                                color: Colors.redAccent,
                                onTap: () async {
                                  Navigator.pop(ctx);
                                  await provider.moveToTrash(id);
                                  SoundService.instance.play(SoundEvent.trash,
                                      settings: settings);
                                  if (mounted) {
                                    AppToast.show(context,
                                        message: 'Moved "$title" to trash');
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 3D Pushpin at top center
                  Positioned(
                    top: -7,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _buildPushpinWidget(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _popupActionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: appFont(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3D Red Pushpin matching Image 2
  Widget _buildPushpinWidget() {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          radius: 0.8,
          colors: [
            Color(0xFFFF8A80), // Specular light highlight
            Color(0xFFE53935), // Primary red
            Color(0xFFB71C1C), // Deep red edge shadow
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 4,
            offset: const Offset(1, 2),
          ),
        ],
      ),
    );
  }

  /// 6-Button Action Bar on Selected Note matching mockup in Image 2
  Widget _buildActionBar(BuildContext context, Map<String, dynamic> thought) {
    final provider = context.read<ThoughtProvider>();
    final settings = context.read<SettingsService>();
    final id = thought['id'] as String;
    final title = (thought['title'] as String?)?.isNotEmpty == true
        ? thought['title'] as String
        : 'Note';

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFF1E222B).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 1: Mark done
          _actionIcon(
            icon: Icons.check,
            tooltip: 'Mark done',
            color: const Color(0xFFFFD54F),
            onTap: () async {
              setState(() => _selectedThoughtId = null);
              final rootCtx = GlobalErrorHandler.navigatorKey.currentContext ?? context;
              debugPrint('[RewardFlow] mini.markDone id=$id');
              final xp = await provider.markDone(id, true);
              final reward = GamificationService.instance.consumePendingRewardEvent();
              debugPrint('[RewardFlow] mini.consume reward=${reward != null}');
              if (rootCtx.mounted) {
                RewardFeedbackService.showTaskReward(rootCtx, xp: xp, settings: settings);
                if (reward != null) {
                  await RewardFeedbackService.maybeShowLevelUp(rootCtx, event: reward, settings: settings);
                }
                await RewardFeedbackService.maybeShowDailyGoal(rootCtx, game: GamificationService.instance, settings: settings);
              }
            },
          ),

          // 2: Split into smaller tasks
          _actionIcon(
            icon: Icons.splitscreen,
            tooltip: 'Split into smaller tasks',
            onTap: () {
              setState(() => _selectedThoughtId = null);
              _showSplitDialog(context, thought);
            },
          ),

          // 3: Edit
          _actionIcon(
            icon: Icons.edit_outlined,
            tooltip: 'Edit',
            onTap: () {
              setState(() => _selectedThoughtId = null);
              _showEditDialog(context, thought);
            },
          ),

          // 4: Copy
          _actionIcon(
            icon: Icons.copy_outlined,
            tooltip: 'Copy',
            onTap: () async {
              setState(() => _selectedThoughtId = null);
              await Clipboard.setData(ClipboardData(text: thought['content']?.toString() ?? ''));
              if (mounted) {
                AppToast.show(context, message: 'Copied "$title"');
              }
            },
          ),

          // 5: Remove from board (unpin only)
          _actionIcon(
            icon: Icons.close,
            tooltip: 'Remove from board',
            onTap: () async {
              setState(() => _selectedThoughtId = null);
              await provider.unpinFromBoard(id);
              if (mounted) {
                AppToast.show(
                  context,
                  message: 'Removed "$title" from board (kept in list)',
                );
              }
            },
          ),

          // 6: Delete to trash
          _actionIcon(
            icon: Icons.delete_outline,
            tooltip: 'Delete (to Trash)',
            color: Colors.redAccent,
            onTap: () async {
              setState(() => _selectedThoughtId = null);
              await provider.moveToTrash(id);
              SoundService.instance.play(SoundEvent.trash, settings: settings);
              if (mounted) {
                AppToast.show(context, message: 'Moved "$title" to trash');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return IconButton(
      icon: Icon(icon, size: 16, color: color ?? Colors.white),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      onPressed: onTap,
    );
  }
}
