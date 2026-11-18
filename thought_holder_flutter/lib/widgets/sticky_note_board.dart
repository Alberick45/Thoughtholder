import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../sound_service.dart';
import '../thought_provider.dart';
import '../settings_modal.dart';

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

  Color _getNoteColor(int index) {
    return kStickyNoteColors[index % kStickyNoteColors.length];
  }

  void _onBoardSecondaryTapDown(BuildContext context, TapDownDetails details) {
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
      BuildContext context, Offset globalPos, Map<String, dynamic> thought) async {
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
        await provider.markDone(id, true);
        SoundService.instance.play(SoundEvent.save, settings: settings);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Marked "$title" as done'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 94),
            ),
          );
        }
        break;
      case 'split':
        _showSplitDialog(context, thought);
        break;
      case 'edit':
        _showEditDialog(context, thought);
        break;
      case 'copy':
        await provider.copyThought(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Duplicated "$title"'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 94),
            ),
          );
        }
        break;
      case 'unpin':
        await provider.unpinFromBoard(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Removed "$title" from board (kept in list)'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 94),
            ),
          );
        }
        break;
      case 'trash':
        await provider.moveToTrash(id);
        SoundService.instance.play(SoundEvent.trash, settings: settings);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Moved "$title" to trash'),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.only(bottom: 80, left: 16, right: 94),
            ),
          );
        }
        break;
    }
  }

  void _showCreateStickyNoteDialog(BuildContext context) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final bucketCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333B48)),
        ),
        title: Text(
          'New Sticky Note',
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
              const SizedBox(height: 12),
              TextField(
                controller: bucketCtrl,
                style: appFont(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Bucket (optional)',
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
              final text = contentCtrl.text.trim();
              final title = titleCtrl.text.trim();
              final bucket = bucketCtrl.text.trim();
              if (text.isEmpty && title.isEmpty) return;

              Navigator.pop(ctx);
              final provider = context.read<ThoughtProvider>();
              final thought = await provider.addThought(
                text.isNotEmpty ? text : title,
                'thought',
                bucket: bucket.isNotEmpty ? bucket : null,
              );
              if (title.isNotEmpty) {
                await provider.updateThoughtTitle(thought['id'], title,
                    titleSource: 'user');
              }
              await provider.pinToBoard(thought['id']);
            },
            child: const Text('Pin to Board'),
          ),
        ],
      ),
    );
  }

  void _showPinListPicker(BuildContext context, {required bool isSorted}) {
    final provider = context.read<ThoughtProvider>();
    final thoughts = isSorted
        ? provider.sortedThoughts.where((t) => !provider.isPinned(t)).toList()
        : provider.unsortedThoughts.where((t) => !provider.isPinned(t)).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
          width: 440,
          height: 380,
          child: thoughts.isEmpty
              ? Center(
                  child: Text(
                    'No available thoughts to pin',
                    style: appFont(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  itemCount: thoughts.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: Color(0xFF333B48), height: 1),
                  itemBuilder: (context, index) {
                    final t = thoughts[index];
                    final title = (t['title'] as String?)?.isNotEmpty == true
                        ? t['title'] as String
                        : (t['content'] as String? ?? 'Untitled');
                    final bucket = t['bucket'] as String? ?? 'Unsorted';

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: appFont(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        bucket,
                        style: appFont(color: Colors.grey, fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.push_pin_outlined,
                            color: Color(0xFFFFD54F), size: 20),
                        tooltip: 'Pin to board',
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final ok = await provider.pinToBoard(t['id']);
                          if (!ok && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Board is full (8/8). Remove a note from the board first.'),
                                behavior: SnackBarBehavior.floating,
                                margin: EdgeInsets.only(
                                    bottom: 80, left: 16, right: 94),
                              ),
                            );
                          }
                        },
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

  void _showSplitDialog(BuildContext context, Map<String, dynamic> thought) {
    final provider = context.read<ThoughtProvider>();
    final content = thought['content'] as String? ?? '';
    final title = thought['title'] as String? ?? '';
    final bucket = thought['bucket'] as String? ?? 'General';
    final ctrl = TextEditingController();

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
              final result = await provider.splitThought(thought['id'], lines);

              if (mounted) {
                if (result.pinnedCount < result.createdCount) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Created ${result.createdCount} tasks in "$bucket". Pinned ${result.pinnedCount}; remaining tasks kept in bucket (board full 8/8).',
                      ),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.only(
                          bottom: 80, left: 16, right: 94),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Created and pinned ${result.createdCount} tasks in "$bucket".',
                      ),
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.only(
                          bottom: 80, left: 16, right: 94),
                    ),
                  );
                }
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
              await provider.updateThoughtTitle(thought['id'], titleCtrl.text.trim(),
                  titleSource: 'user');
              await provider.updateContent(thought['id'], contentCtrl.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
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
                    '$pinnedCount / 8 pinned',
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
                        return SizedBox(
                          width: 180,
                          child: GestureDetector(
                            onTap: widget.onToggleExpand,
                            onSecondaryTapDown: (details) => _showNoteContextMenu(
                                context, details.globalPosition, thought),
                            child: _buildStickyNoteCard(
                              thought: thought,
                              color: color,
                              isSelected: false,
                              cellWidth: 180,
                              cellHeight: 110,
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
            // Top Bar: Prominent Sort button on left, Title center, Pinned count + Settings right (matching Image 2)
            Row(
              children: [
                // Top-Left: "≡ Sort" button matching Image 2
                InkWell(
                  onTap: widget.onOpenSorted,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E222B),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF333B48), width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu, size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Sort',
                          style: appFont(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // Center Title: BRAIN DUMP • BOARD
                Text(
                  'BRAIN DUMP • BOARD',
                  style: appFont(
                    color: const Color(0xFFFFD54F),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                    fontSize: 15,
                  ),
                ),

                const Spacer(),

                // Pinned badge (e.g. 7 / 8 pinned)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E222B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFFD54F).withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    '$pinnedCount / 8 pinned',
                    style: appFont(
                      color: const Color(0xFFFFD54F),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),

                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.wb_sunny_outlined,
                    color: Color(0xFFFFD54F),
                    size: 20,
                  ),
                  tooltip: 'Settings: connect Groq',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => const SettingsModal(),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Sticky Note 4 x 2 Grid (Up to 8 notes)
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
                    itemCount: 8,
                    itemBuilder: (context, slotIndex) {
                      if (slotIndex < pinnedCount) {
                        final thought = pinned[slotIndex];
                        final isSelected = thought['id'] == _selectedThoughtId;
                        final color = _getNoteColor(slotIndex);

                        return DragTarget<int>(
                          onAcceptWithDetails: (details) {
                            final fromIndex = details.data;
                            if (fromIndex != slotIndex) {
                              provider.reorderBoard(fromIndex, slotIndex);
                            }
                          },
                          builder: (context, candidateData, rejectedData) {
                            return LongPressDraggable<int>(
                              data: slotIndex,
                              feedback: Material(
                                color: Colors.transparent,
                                child: SizedBox(
                                  width: cellWidth,
                                  height: cellHeight,
                                  child: Opacity(
                                    opacity: 0.85,
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
                              childWhenDragging: Opacity(
                                opacity: 0.3,
                                child: _buildStickyNoteCard(
                                  thought: thought,
                                  color: color,
                                  isSelected: false,
                                  cellWidth: cellWidth,
                                  cellHeight: cellHeight,
                                ),
                              ),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_selectedThoughtId == thought['id']) {
                                      _selectedThoughtId = null;
                                    } else {
                                      _selectedThoughtId = thought['id'];
                                    }
                                  });
                                },
                                onSecondaryTapDown: (details) =>
                                    _showNoteContextMenu(
                                        context, details.globalPosition, thought),
                                child: _buildStickyNoteCard(
                                  thought: thought,
                                  color: color,
                                  isSelected: isSelected,
                                  cellWidth: cellWidth,
                                  cellHeight: cellHeight,
                                ),
                              ),
                            );
                          },
                        );
                      } else {
                        // Empty Slot (Dashed outline)
                        final slotsLeft = 8 - pinnedCount;
                        return GestureDetector(
                          onTap: () => _showCreateStickyNoteDialog(context),
                          onSecondaryTapDown: (details) =>
                              _onBoardSecondaryTapDown(context, details),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF262C38),
                                width: 1.5,
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.add,
                                        size: 22, color: Color(0xFF4B5563)),
                                    const SizedBox(height: 6),
                                    Text(
                                      '$slotsLeft slot${slotsLeft == 1 ? '' : 's'} left',
                                      style: appFont(
                                        color: const Color(0xFF9CA3AF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'right-click anywhere to add',
                                      textAlign: TextAlign.center,
                                      style: appFont(
                                        color: const Color(0xFF4B5563),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),

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

  Widget _buildStickyNoteCard({
    required Map<String, dynamic> thought,
    required Color color,
    required bool isSelected,
    required double cellWidth,
    required double cellHeight,
  }) {
    final title = (thought['title'] as String?)?.isNotEmpty == true
        ? thought['title'] as String
        : (thought['content'] as String? ?? 'Untitled');
    final content = thought['content'] as String? ?? '';
    final bucket = (thought['bucket'] as String?)?.trim() ?? '';
    final whenVal = thought['when_val'] as String? ?? '';
    final timeVal = thought['time_val'] as String? ?? '';

    String tagLabel = '';
    if (whenVal.isNotEmpty && whenVal != 'Soon') {
      tagLabel = 'due $whenVal'.toLowerCase();
    } else if (timeVal.isNotEmpty) {
      tagLabel = timeVal.toLowerCase();
    } else {
      tagLabel = 'quick';
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main Note Body
        Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: isSelected ? 14 : 8,
                offset: const Offset(2, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title (bold dark text)
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: appFont(
                  color: const Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),

              // Content Preview (2-3 lines)
              Expanded(
                child: Text(
                  content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(
                    color: const Color(0xFF334155),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),

              const SizedBox(height: 6),

              // Bottom Badges: Bucket pill on left, Effort/Due on right
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Bucket badge pill
                  if (bucket.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
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
                          fontSize: 10,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),

                  // Due / effort tag
                  Text(
                    tagLabel,
                    style: appFont(
                      color: const Color(0xFF475569),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Direct Positioned 3D Red Pushpin at top center (NO Stateless wrapper!)
        Positioned(
          top: -6,
          left: 0,
          right: 0,
          child: Center(
            child: _buildPushpinWidget(),
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
              await provider.markDone(id, true);
              SoundService.instance.play(SoundEvent.save, settings: settings);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Marked "$title" as done'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(
                        bottom: 80, left: 16, right: 94),
                  ),
                );
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
              await provider.copyThought(id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Duplicated "$title"'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(
                        bottom: 80, left: 16, right: 94),
                  ),
                );
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Removed "$title" from board (kept in list)'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(
                        bottom: 80, left: 16, right: 94),
                  ),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Moved "$title" to trash'),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.only(
                        bottom: 80, left: 16, right: 94),
                  ),
                );
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
