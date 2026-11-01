import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'thought_provider.dart';
import 'settings_service.dart';
import 'app_theme.dart';
import 'database_helper.dart';
import 'sync_identity.dart';
import 'utils/title_generator.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  int _currentPage = 0;
  static const int _pageSize = 9;

  bool _isSelectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showUndoSnackBar(String message, [Future<void> Function()? onUndo]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: appFont(color: Colors.white, fontSize: 14),
        ),
        duration: const Duration(seconds: 6),
        backgroundColor: const Color(0xFF222226),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: onUndo != null
            ? SnackBarAction(
                label: 'Undo',
                textColor: AppColors.of(context.read<SettingsService>().theme).gold,
                onPressed: () async {
                  await onUndo();
                },
              )
            : null,
      ),
    );
  }

  Future<void> _restoreThoughtState(
    Map<String, dynamic> snapshot,
    ThoughtProvider provider,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final deviceId = DatabaseHelper.currentDeviceId;
    await db.rawUpdate('''
      UPDATE thoughts SET
        done = ?,
        status = ?,
        done_at = ?,
        trashed = ?,
        trashed_at = ?,
        bucket = ?,
        bucket_id = ?,
        content = ?,
        edited_at = ?,
        updated_at = ?,
        updated_by = ?,
        revision = revision + 1
      WHERE id = ?
    ''', [
      snapshot['done'] ?? 1,
      snapshot['status'] ?? 'completed',
      snapshot['done_at'],
      snapshot['trashed'] ?? 0,
      snapshot['trashed_at'],
      snapshot['bucket'],
      snapshot['bucket_id'],
      snapshot['content'],
      snapshot['edited_at'],
      Hlc.now(deviceId).toString(),
      deviceId,
      snapshot['id'],
    ]);
    await provider.loadThoughts();
  }

  Future<void> _restoreMultipleThoughts(
    List<Map<String, dynamic>> snapshots,
    ThoughtProvider provider,
  ) async {
    final db = await DatabaseHelper.instance.database;
    final deviceId = DatabaseHelper.currentDeviceId;
    for (final snapshot in snapshots) {
      await db.rawUpdate('''
        UPDATE thoughts SET
          done = ?,
          status = ?,
          done_at = ?,
          trashed = ?,
          trashed_at = ?,
          bucket = ?,
          bucket_id = ?,
          content = ?,
          edited_at = ?,
          updated_at = ?,
          updated_by = ?,
          revision = revision + 1
        WHERE id = ?
      ''', [
        snapshot['done'] ?? 1,
        snapshot['status'] ?? 'completed',
        snapshot['done_at'],
        snapshot['trashed'] ?? 0,
        snapshot['trashed_at'],
        snapshot['bucket'],
        snapshot['bucket_id'],
        snapshot['content'],
        snapshot['edited_at'],
        Hlc.now(deviceId).toString(),
        deviceId,
        snapshot['id'],
      ]);
    }
    await provider.loadThoughts();
  }

  Future<void> _putBackSingleIdea(
    BuildContext context,
    Map<String, dynamic> idea,
    ThoughtProvider provider,
  ) async {
    final snapshot = Map<String, dynamic>.from(idea);
    final originalBucket = (idea['bucket'] as String?)?.trim();
    final bool hasValidBucket = originalBucket != null &&
        originalBucket.isNotEmpty &&
        provider.buckets.any((b) =>
            (b['name'] as String).trim().toLowerCase() ==
            originalBucket.toLowerCase());

    final ideaName = TitleGenerator.getIdeaName(idea);
    String message;
    if (hasValidBucket) {
      await provider.markDone(idea['id'], false);
      message = 'Put back "$ideaName" in $originalBucket.';
    } else {
      await provider.unfileThought(idea['id']);
      await provider.markDone(idea['id'], false);
      message = 'Put back "$ideaName" in Unsorted.';
    }

    _showUndoSnackBar(message, () => _restoreThoughtState(snapshot, provider));
  }

  Future<void> _putBackSelectedIdeas(
    BuildContext context,
    ThoughtProvider provider,
    List<Map<String, dynamic>> allDoneIdeas,
    AppColors colors,
  ) async {
    final selectedIdeas = allDoneIdeas
        .where((t) => _selectedIds.contains(t['id']))
        .take(50)
        .toList();
    final count = selectedIdeas.length;
    if (count == 0) return;

    final snapshots =
        selectedIdeas.map((t) => Map<String, dynamic>.from(t)).toList();
    final db = await DatabaseHelper.instance.database;
    final deviceId = DatabaseHelper.currentDeviceId;

    for (final idea in selectedIdeas) {
      final originalBucket = (idea['bucket'] as String?)?.trim();
      final bool hasValidBucket = originalBucket != null &&
          originalBucket.isNotEmpty &&
          provider.buckets.any((b) =>
              (b['name'] as String).trim().toLowerCase() ==
              originalBucket.toLowerCase());

      final bucketToSet = hasValidBucket ? originalBucket : null;
      String? bucketIdToSet;
      if (bucketToSet != null) {
        final bMatch = provider.buckets.firstWhere(
          (b) =>
              (b['name'] as String).trim().toLowerCase() ==
              bucketToSet.toLowerCase(),
          orElse: () => {},
        );
        if (bMatch.isNotEmpty) {
          bucketIdToSet = bMatch['id'] as String?;
        }
      }

      await db.rawUpdate('''
        UPDATE thoughts SET
          done = 0,
          status = 'active',
          done_at = NULL,
          bucket = ?,
          bucket_id = ?,
          updated_at = ?,
          updated_by = ?,
          revision = revision + 1
        WHERE id = ?
      ''', [
        bucketToSet,
        bucketIdToSet,
        Hlc.now(deviceId).toString(),
        deviceId,
        idea['id'],
      ]);
    }

    await provider.loadThoughts();

    setState(() {
      _isSelectMode = false;
      _selectedIds.clear();
    });

    final noun = count == 1 ? 'idea' : 'ideas';
    _showUndoSnackBar(
      'Put back $count $noun.',
      () => _restoreMultipleThoughts(snapshots, provider),
    );
  }

  Future<void> _trashSelectedIdeas(
    BuildContext context,
    ThoughtProvider provider,
    List<Map<String, dynamic>> allDoneIdeas,
    AppColors colors,
  ) async {
    final selectedIdeas = allDoneIdeas
        .where((t) => _selectedIds.contains(t['id']))
        .take(50)
        .toList();
    final count = selectedIdeas.length;
    if (count == 0) return;

    final snapshots =
        selectedIdeas.map((t) => Map<String, dynamic>.from(t)).toList();
    final db = await DatabaseHelper.instance.database;
    final deviceId = DatabaseHelper.currentDeviceId;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final idea in selectedIdeas) {
      await db.rawUpdate('''
        UPDATE thoughts SET
          trashed = 1,
          status = 'vaulted_trash',
          trashed_at = ?,
          updated_at = ?,
          updated_by = ?,
          revision = revision + 1
        WHERE id = ?
      ''', [
        now,
        Hlc.now(deviceId).toString(),
        deviceId,
        idea['id'],
      ]);
    }

    await provider.loadThoughts();

    setState(() {
      _isSelectMode = false;
      _selectedIds.clear();
    });

    final noun = count == 1 ? 'idea' : 'ideas';
    _showUndoSnackBar(
      'Moved $count $noun to Trash.',
      () => _restoreMultipleThoughts(snapshots, provider),
    );
  }

  void _openIdeaPreview(
    BuildContext context,
    Map<String, dynamic> idea,
    ThoughtProvider provider,
    AppColors colors,
  ) {
    final isDesktop = (!kIsWeb &&
            (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) &&
        MediaQuery.of(context).size.width >= 600;

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
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
            child: _PreviewSheetContent(
              idea: idea,
              colors: colors,
              provider: provider,
              onPutBack: () {
                Navigator.pop(ctx);
                _putBackSingleIdea(context, idea, provider);
              },
              onPutBackAnother: () {
                Navigator.pop(ctx);
                _showChooseBucketPopup(
                  context: context,
                  provider: provider,
                  idea: idea,
                  colors: colors,
                );
              },
              onEdit: () {
                Navigator.pop(ctx);
                _showEditIdeaDialog(context, provider, idea, colors);
              },
              onCopy: () {
                final content = idea['content'] as String? ?? '';
                Clipboard.setData(ClipboardData(text: content));
                _showUndoSnackBar('Copied idea text to clipboard.');
              },
              onMoveToTrash: () async {
                Navigator.pop(ctx);
                final snapshot = Map<String, dynamic>.from(idea);
                final ideaName = TitleGenerator.getIdeaName(idea);
                await provider.moveToTrash(idea['id']);
                _showUndoSnackBar(
                  'Moved "$ideaName" to Trash.',
                  () => _restoreThoughtState(snapshot, provider),
                );
              },
              onClose: () => Navigator.pop(ctx),
            ),
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
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: BoxDecoration(
            color: colors.bg,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: colors.line),
          ),
          child: _PreviewSheetContent(
            idea: idea,
            colors: colors,
            provider: provider,
            onPutBack: () {
              Navigator.pop(ctx);
              _putBackSingleIdea(context, idea, provider);
            },
            onPutBackAnother: () {
              Navigator.pop(ctx);
              _showChooseBucketPopup(
                context: context,
                provider: provider,
                idea: idea,
                colors: colors,
              );
            },
            onEdit: () {
              Navigator.pop(ctx);
              _showEditIdeaDialog(context, provider, idea, colors);
            },
            onCopy: () {
              final content = idea['content'] as String? ?? '';
              Clipboard.setData(ClipboardData(text: content));
              _showUndoSnackBar('Copied idea text to clipboard.');
            },
            onMoveToTrash: () async {
              Navigator.pop(ctx);
              final snapshot = Map<String, dynamic>.from(idea);
              final ideaName = TitleGenerator.getIdeaName(idea);
              await provider.moveToTrash(idea['id']);
              _showUndoSnackBar(
                'Moved "$ideaName" to Trash.',
                () => _restoreThoughtState(snapshot, provider),
              );
            },
            onClose: () => Navigator.pop(ctx),
          ),
        ),
      );
    }
  }

  void _showEditIdeaDialog(
    BuildContext context,
    ThoughtProvider provider,
    Map<String, dynamic> idea,
    AppColors colors,
  ) {
    final thoughtId = idea['thought_id'] as String? ?? 'LOG';
    final currentTitle = TitleGenerator.getIdeaName(idea);
    final titleController = TextEditingController(text: currentTitle);
    final contentController =
        TextEditingController(text: idea['content'] as String? ?? '');
    bool isSuggesting = false;
    String? suggestionStatus;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: colors.bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.line),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Edit Idea',
                style: appFont(
                  color: colors.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(
                thoughtId,
                style: appFont(
                  color: colors.mute.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      fillColor: colors.card,
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
                      hintStyle: appFont(color: colors.mute, fontSize: 14),
                      filled: true,
                      fillColor: colors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colors.gold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                minimumSize: const Size(80, 48),
              ),
              child: Text(
                'Cancel',
                style: appFont(color: colors.mute, fontSize: 14),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                foregroundColor: colors.bg,
                minimumSize: const Size(100, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final newContent = contentController.text.trim();
                final newTitle = titleController.text.trim();
                if (newContent.isNotEmpty) {
                  Navigator.pop(ctx);
                  final snapshot = Map<String, dynamic>.from(idea);
                  final now = DateTime.now().millisecondsSinceEpoch;
                  if (newTitle.isNotEmpty && newTitle != currentTitle) {
                    await provider.updateThoughtTitle(idea['id'], newTitle, titleSource: 'user');
                  }
                  await provider.updateContent(idea['id'], newContent, editedAt: now);
                  _showUndoSnackBar(
                    'Updated "${newTitle.isNotEmpty ? newTitle : currentTitle}".',
                    () => _restoreThoughtState(snapshot, provider),
                  );
                } else {
                  Navigator.pop(ctx);
                }
              },
              child: Text(
                'Save',
                style: appFont(
                  color: colors.bg,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            final availableBuckets = provider.buckets.where((b) {
              final name = (b['name'] as String).trim();
              if (currentBucket != null && currentBucket.isNotEmpty) {
                if (name.toLowerCase() == currentBucket.toLowerCase()) {
                  return false;
                }
              }
              return true;
            }).toList();

            final sortedByUsage =
                List<Map<String, dynamic>>.from(availableBuckets);
            sortedByUsage.sort((a, b) {
              final countA = provider.getIdeaCountForBucket(a['name'] as String);
              final countB = provider.getIdeaCountForBucket(b['name'] as String);
              if (countB != countA) {
                return countB.compareTo(countA);
              }
              return (a['name'] as String)
                  .toLowerCase()
                  .compareTo((b['name'] as String).toLowerCase());
            });

            final top3 = sortedByUsage.take(3).toList();
            final rest = sortedByUsage.skip(3).toList();
            rest.sort((a, b) => (a['name'] as String)
                .toLowerCase()
                .compareTo((b['name'] as String).toLowerCase()));

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
                final snapshot = Map<String, dynamic>.from(idea);
                final canonicalName = await provider.addBucket(targetBucket);
                final destination =
                    canonicalName.isNotEmpty ? canonicalName : targetBucket;

                await provider.fileThought(idea['id'], destination);
                await provider.markDone(idea['id'], false);

                if (modalCtx.mounted && Navigator.canPop(modalCtx)) {
                  Navigator.pop(modalCtx);
                }

                _showUndoSnackBar(
                  'Put back "$ideaName" in $destination.',
                  () => _restoreThoughtState(snapshot, provider),
                );
              } catch (e) {
                setPopupState(() {
                  isAdding = false;
                  errorMessage =
                      'Could not move idea to bucket. Please try again.';
                });
              }
            }

            return Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                  maxWidth: 600,
                ),
                child: Container(
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
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
                                  style: appFont(color: colors.mute, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                            hintStyle:
                                appFont(color: colors.mute, fontSize: 14),
                            prefixIcon: Icon(Icons.search,
                                color: colors.mute, size: 20),
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
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            if (showCreateRow) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: colors.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: colors.gold.withValues(alpha: 0.6)),
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text(
                                    query.isEmpty
                                        ? 'No other buckets available'
                                        : 'No buckets matching "$query"',
                                    style: appFont(
                                        color: colors.mute, fontSize: 14),
                                  ),
                                ),
                              ),
                            ...filteredBuckets.map((b) {
                              final name = b['name'] as String;
                              final iconKey =
                                  (b['icon'] as String?) ?? 'folder';
                              final iconData =
                                  kBucketIcons[iconKey] ?? Icons.folder_outlined;
                              final count =
                                  provider.getIdeaCountForBucket(name);

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
                                                color: colors.mute,
                                                fontSize: 12),
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
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);
    final provider = context.watch<ThoughtProvider>();

    final doneIdeas = provider.thoughts.where((t) {
      final done = provider.isDone(t);
      final trashed = provider.isTrashed(t);
      if (!done || trashed) return false;
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      final content = (t['content'] ?? '').toString().toLowerCase();
      final bucket = (t['bucket'] ?? '').toString().toLowerCase();
      final thoughtId = (t['thought_id'] ?? '').toString().toLowerCase();
      final title = (t['title'] ?? '').toString().toLowerCase();
      return content.contains(q) ||
          bucket.contains(q) ||
          thoughtId.contains(q) ||
          title.contains(q);
    }).toList();

    doneIdeas.sort((a, b) {
      final int dateA = (a['done_at'] as num?)?.toInt() ??
          (a['created_at'] as num?)?.toInt() ??
          0;
      final int dateB = (b['done_at'] as num?)?.toInt() ??
          (b['created_at'] as num?)?.toInt() ??
          0;
      return dateB.compareTo(dateA);
    });

    final isGrid = settings.historyGridView;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 600;
    final columns = isWide ? 3 : 2;

    final totalCount = doneIdeas.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 999999);
    final safeCurrentPage = _currentPage.clamp(0, totalPages - 1);
    final pagedIdeas =
        doneIdeas.skip(safeCurrentPage * _pageSize).take(_pageSize).toList();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        title: Text(
          _isSelectMode
              ? '${_selectedIds.length} selected'
              : 'History',
          style: appFont(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          if (!_isSelectMode)
            TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: colors.gold,
              ),
              icon: Icon(Icons.checklist, color: colors.gold, size: 20),
              label: Text(
                'Select',
                style: appFont(
                  color: colors.gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed: () {
                setState(() {
                  _isSelectMode = true;
                  _selectedIds.clear();
                });
              },
            )
          else ...[
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: colors.gold,
              ),
              onPressed: () {
                setState(() {
                  final maxSelectable = math.min(50, doneIdeas.length);
                  if (_selectedIds.length >= maxSelectable &&
                      maxSelectable > 0) {
                    _selectedIds.clear();
                  } else {
                    _selectedIds.clear();
                    for (final idea in doneIdeas.take(50)) {
                      _selectedIds.add(idea['id'] as String);
                    }
                  }
                });
              },
              child: Text(
                _selectedIds.length >= math.min(50, doneIdeas.length) &&
                        doneIdeas.isNotEmpty
                    ? 'Deselect all'
                    : 'Select all (${math.min(50, doneIdeas.length)})',
                style: appFont(
                  color: colors.gold,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: colors.mute,
              ),
              onPressed: () {
                setState(() {
                  _isSelectMode = false;
                  _selectedIds.clear();
                });
              },
              child: Text(
                'Cancel',
                style: appFont(color: colors.mute, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: _isSelectMode
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.card,
                border: Border(top: BorderSide(color: colors.line)),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.gold,
                            foregroundColor: colors.bg,
                            disabledBackgroundColor:
                                colors.gold.withValues(alpha: 0.25),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : () => _putBackSelectedIdeas(
                                  context, provider, doneIdeas, colors),
                          icon: const Icon(Icons.replay_outlined, size: 20),
                          label: Text(
                            _selectedIds.isEmpty
                                ? 'Put back'
                                : 'Put back (${_selectedIds.length})',
                            style: appFont(
                              color: _selectedIds.isEmpty
                                  ? colors.mute
                                  : colors.bg,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
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
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.bad,
                            side: BorderSide(
                              color: _selectedIds.isEmpty
                                  ? colors.line
                                  : colors.bad,
                            ),
                            disabledForegroundColor: colors.mute,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : () => _trashSelectedIdeas(
                                  context, provider, doneIdeas, colors),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          label: Text(
                            _selectedIds.isEmpty
                                ? 'Move to Trash'
                                : 'Move to Trash (${_selectedIds.length})',
                            style: appFont(
                              color: _selectedIds.isEmpty
                                  ? colors.mute
                                  : colors.bad,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: Column(
          children: [
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.line),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search completed ideas...',
                  hintStyle: appFont(color: colors.mute, fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: colors.mute, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, color: colors.mute, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _search = '';
                              _currentPage = 0;
                            });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) {
                  setState(() {
                    _search = v.trim();
                    _currentPage = 0;
                  });
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isGrid ? colors.gold : colors.card,
                    minimumSize: const Size(100, 48),
                    foregroundColor: isGrid ? colors.bg : colors.text,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: isGrid ? colors.gold : colors.line,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.grid_view, size: 18),
                  onPressed: () async {
                    if (!isGrid) await settings.setHistoryGridView(true);
                  },
                  label: const Text('Grid'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: !isGrid ? colors.gold : colors.card,
                    minimumSize: const Size(100, 48),
                    foregroundColor: !isGrid ? colors.bg : colors.text,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: !isGrid ? colors.gold : colors.line,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.view_list, size: 18),
                  onPressed: () async {
                    if (isGrid) await settings.setHistoryGridView(false);
                  },
                  label: const Text('List'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: totalCount == 0
                  ? Center(
                      child: Text(
                        _search.isEmpty
                            ? 'No completed ideas yet'
                            : 'No completed ideas match "$_search"',
                        style: appFont(color: colors.mute, fontSize: 15),
                      ),
                    )
                  : isGrid
                      ? GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisExtent: 140.0,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                          itemCount: pagedIdeas.length,
                          itemBuilder: (context, i) {
                            final idea = pagedIdeas[i];
                            final id = idea['id'] as String;
                            final isSelected = _selectedIds.contains(id);
                            return _FinishedCard(
                              idea: idea,
                              colors: colors,
                              isSelectMode: _isSelectMode,
                              isSelected: isSelected,
                              onTap: () {
                                if (_isSelectMode) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIds.remove(id);
                                    } else {
                                      if (_selectedIds.length >= 50) {
                                        _showUndoSnackBar(
                                            'Maximum 50 ideas can be selected at once.');
                                      } else {
                                        _selectedIds.add(id);
                                      }
                                    }
                                  });
                                } else {
                                  _openIdeaPreview(
                                      context, idea, provider, colors);
                                }
                              },
                            );
                          },
                        )
                      : ListView.builder(
                          itemCount: pagedIdeas.length,
                          itemBuilder: (context, i) {
                            final idea = pagedIdeas[i];
                            final id = idea['id'] as String;
                            final isSelected = _selectedIds.contains(id);
                            return _FinishedTile(
                              idea: idea,
                              colors: colors,
                              isSelectMode: _isSelectMode,
                              isSelected: isSelected,
                              onTap: () {
                                if (_isSelectMode) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIds.remove(id);
                                    } else {
                                      if (_selectedIds.length >= 50) {
                                        _showUndoSnackBar(
                                            'Maximum 50 ideas can be selected at once.');
                                      } else {
                                        _selectedIds.add(id);
                                      }
                                    }
                                  });
                                } else {
                                  _openIdeaPreview(
                                      context, idea, provider, colors);
                                }
                              },
                            );
                          },
                        ),
            ),
            if (totalPages > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Showing ${safeCurrentPage * _pageSize + 1}–${math.min((safeCurrentPage + 1) * _pageSize, totalCount)} of $totalCount',
                    style: appFont(color: colors.mute, fontSize: 12),
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          side: BorderSide(color: colors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: safeCurrentPage > 0
                            ? () => setState(
                                () => _currentPage = safeCurrentPage - 1)
                            : null,
                        child: Icon(
                          Icons.chevron_left,
                          color: safeCurrentPage > 0
                              ? colors.text
                              : colors.mute,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          '${safeCurrentPage + 1} / $totalPages',
                          style: appFont(
                            color: colors.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          side: BorderSide(color: colors.line),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: safeCurrentPage < totalPages - 1
                            ? () => setState(
                                () => _currentPage = safeCurrentPage + 1)
                            : null,
                        child: Icon(
                          Icons.chevron_right,
                          color: safeCurrentPage < totalPages - 1
                              ? colors.text
                              : colors.mute,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FinishedCard extends StatelessWidget {
  final Map<String, dynamic> idea;
  final AppColors colors;
  final bool isSelectMode;
  final bool isSelected;
  final VoidCallback onTap;

  const _FinishedCard({
    required this.idea,
    required this.colors,
    required this.isSelectMode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = TitleGenerator.getIdeaName(idea);
    final timestamp = IdeaFormatters.formatReadableTimestamp(
        idea['done_at'] as int? ?? idea['created_at'] as int?);
    final captureIcon =
        IdeaFormatters.getCaptureIcon(idea['audio_path'] ?? idea['type']);
    final content = (idea['content'] as String? ?? '').trim();
    final bucket = (idea['bucket'] as String?)?.trim() ?? '';

    return Material(
      color: colors.card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? colors.gold : colors.line,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          padding: const EdgeInsets.all(12.0),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: isSelectMode ? 24.0 : 0.0),
                    child: Text(
                      name,
                      style: appFont(
                        color: colors.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        height: 1.25,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: EdgeInsets.only(right: isSelectMode ? 24.0 : 0.0),
                    child: Text(
                      content.isNotEmpty ? content : '(empty idea)',
                      style: appFont(
                        color: colors.text,
                        fontSize: 12,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      if (captureIcon != null) ...[
                        Icon(captureIcon, size: 12, color: colors.mute),
                        const SizedBox(width: 4),
                      ],
                      if (timestamp.isNotEmpty) ...[
                        Flexible(
                          child: Text(
                            timestamp,
                            style: appFont(color: colors.mute, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      if (timestamp.isNotEmpty && bucket.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text('·',
                              style: appFont(color: colors.mute, fontSize: 11)),
                        ),
                      if (bucket.isNotEmpty) ...[
                        Icon(Icons.folder_outlined,
                            size: 12, color: colors.gold),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            bucket,
                            style: appFont(
                              color: colors.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (isSelectMode)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? colors.gold
                          : colors.card.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? colors.gold : colors.mute,
                        width: 1.5,
                      ),
                    ),
                    child: isSelected
                        ? Icon(Icons.check, size: 14, color: colors.bg)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FinishedTile extends StatelessWidget {
  final Map<String, dynamic> idea;
  final AppColors colors;
  final bool isSelectMode;
  final bool isSelected;
  final VoidCallback onTap;

  const _FinishedTile({
    required this.idea,
    required this.colors,
    required this.isSelectMode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = TitleGenerator.getIdeaName(idea);
    final timestamp = IdeaFormatters.formatReadableTimestamp(
        idea['done_at'] as int? ?? idea['created_at'] as int?);
    final captureIcon =
        IdeaFormatters.getCaptureIcon(idea['audio_path'] ?? idea['type']);
    final bucket = (idea['bucket'] as String?)?.trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? colors.gold : colors.line,
          width: isSelected ? 1.8 : 1.0,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: isSelectMode
            ? Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colors.gold
                      : colors.card.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? colors.gold : colors.mute,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 14, color: colors.bg)
                    : null,
              )
            : null,
        title: Text(
          name,
          style: appFont(
            color: colors.gold,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            if (captureIcon != null) ...[
              Icon(captureIcon, size: 12, color: colors.mute),
              const SizedBox(width: 4),
            ],
            if (timestamp.isNotEmpty) ...[
              Text(timestamp, style: appFont(color: colors.mute, fontSize: 11)),
            ],
            if (timestamp.isNotEmpty && bucket.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('·',
                    style: appFont(color: colors.mute, fontSize: 11)),
              ),
            if (bucket.isNotEmpty) ...[
              Icon(Icons.folder_outlined, size: 12, color: colors.gold),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  bucket,
                  style: appFont(
                    color: colors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _PreviewSheetContent extends StatelessWidget {
  final Map<String, dynamic> idea;
  final AppColors colors;
  final ThoughtProvider provider;
  final VoidCallback onPutBack;
  final VoidCallback onPutBackAnother;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onMoveToTrash;
  final VoidCallback onClose;

  const _PreviewSheetContent({
    required this.idea,
    required this.colors,
    required this.provider,
    required this.onPutBack,
    required this.onPutBackAnother,
    required this.onEdit,
    required this.onCopy,
    required this.onMoveToTrash,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final name = TitleGenerator.getIdeaName(idea);
    final thoughtId = idea['thought_id'] as String? ?? 'LOG';
    final bucket = (idea['bucket'] as String?)?.trim();
    final bucketDisplay =
        (bucket != null && bucket.isNotEmpty) ? bucket : 'Unsorted';
    final content = idea['content'] as String? ?? '';
    final timestamp = IdeaFormatters.formatReadableTimestamp(
        idea['done_at'] as int? ?? idea['created_at'] as int?);
    final captureIcon =
        IdeaFormatters.getCaptureIcon(idea['audio_path'] ?? idea['type']);
    final finishedDate = _formatDateTime(idea['done_at'] as int?);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      style: appFont(
                        color: colors.gold,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (captureIcon != null) ...[
                          Icon(captureIcon, size: 12, color: colors.mute),
                          const SizedBox(width: 4),
                        ],
                        if (timestamp.isNotEmpty) ...[
                          Text(
                            timestamp,
                            style: appFont(color: colors.mute, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.card,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: colors.line),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_outlined,
                                  size: 12, color: colors.mute),
                              const SizedBox(width: 4),
                              Text(
                                bucketDisplay,
                                style: appFont(
                                  color: colors.mute,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          thoughtId,
                          style: appFont(
                            color: colors.mute.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: colors.mute, size: 20),
                onPressed: onClose,
                tooltip: 'Close',
              ),
            ],
          ),
          if (finishedDate.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Finished: $finishedDate',
              style: appFont(color: colors.mute, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 260),
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
                  style: appFont(
                    color: colors.text,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Buttons in exact required order, each >= 48px with icon and words:
          // 1. "Put back" (primary, gold)
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onPutBack,
              icon: const Icon(Icons.replay_outlined, size: 20),
              label: const Text('Put back'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.gold,
                foregroundColor: colors.bg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: appFont(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 2. "Put back in another bucket"
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onPutBackAnother,
              icon: Icon(Icons.drive_file_move_outlined,
                  size: 20, color: colors.gold),
              label: Text(
                'Put back in another bucket',
                style: appFont(
                  color: colors.gold,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.gold.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 3. "Edit" and "Copy"
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
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
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
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
            ],
          ),
          const SizedBox(height: 8),

          // 4. "Move to Trash" (with Undo)
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onMoveToTrash,
              icon: Icon(Icons.delete_outline, size: 20, color: colors.bad),
              label: Text(
                'Move to Trash',
                style: appFont(
                  color: colors.bad,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.bad.withValues(alpha: 0.6)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 5. "Close"
          SizedBox(
            height: 48,
            child: TextButton.icon(
              onPressed: onClose,
              icon: Icon(Icons.close, size: 18, color: colors.mute),
              label: Text(
                'Close',
                style: appFont(color: colors.mute, fontSize: 14),
              ),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(int? millis) {
  if (millis == null) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final month = months[dt.month - 1];
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$month ${dt.day}, ${dt.year} $hour:$minute';
}
