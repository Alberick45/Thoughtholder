import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../thought_provider.dart';
import '../utils/app_toast.dart';
import '../utils/title_generator.dart';

/// Service/Helper that intelligently classifies unsorted thoughts into buckets.
class BucketClassifier {
  static const Map<String, List<String>> categoryKeywords = {
    'Groceries': [
      'gari', 'shito', 'paste', 'groundnut', 'bread', 'milk', 'egg', 'eggs', 'butter',
      'rice', 'onion', 'onions', 'tomato', 'tomatoes', 'meat', 'fish', 'chicken', 'market',
      'cook', 'fruit', 'fruits', 'vegetable', 'vegetables', 'food', 'soup', 'stew', 'oil',
      'pepper', 'yam', 'plantain', 'sugar', 'cereal', 'grocery', 'groceries', 'snack',
      'drink', 'beverage', 'water', 'tea', 'coffee', 'salt', 'flour', 'sauce'
    ],
    'Clothes': [
      'pant', 'pants', 'trouser', 'trousers', 'outing pants', 'outing trouser', 'shirt', 'shirts',
      'shoe', 'shoes', 'boot', 'boots', 'sneaker', 'sneakers', 'jacket', 'coat', 'dress',
      'skirt', 'clothes', 'clothing', 'wear', 'outfit', 'iron', 'laundry', 'suit', 'hoodie',
      'shorts', 'sock', 'socks', 'tie', 'belt', 'jeans', 't-shirt', 'polo', 'cap', 'hat'
    ],
    'School': [
      'chapter', 'lit review', 'paper', 'exam', 'exams', 'quiz', 'homework', 'assignment',
      'study', 'thesis', 'lecture', 'course', 'class', 'classes', 'professor', 'student',
      'library', 'campus', 'grades', 'revision', 'umat', 'harvard', 'academic', 'presentation'
    ],
    'Robot': [
      'robot', 'aruco', 'camera', 'esp32', 'raspberry', 'pi', 'arduino', 'waitress robot',
      'solar robot', 'sensor', 'motor', 'hardware', 'cam', 'esp32-cam'
    ],
    'Hobby': [
      'snake', 'keyboard mode', 'game', 'gaming', 'esp32 games', 'hobby', 'music', 'guitar',
      'piano', 'paint', 'art', 'draw', 'sketch', 'novel', 'read book'
    ],
    'Projects': [
      'code', 'python', 'flutter', 'app', 'bug', 'feature', 'repo', 'api', 'git', 'github',
      'server', 'database', 'project', 'deploy', 'backend', 'frontend', 'website'
    ],
    'Finance': [
      'buy', 'pay', 'bill', 'bills', 'money', 'bank', 'rent', 'salary', 'budget', 'dollar',
      'dollars', 'cedis', 'transfer', 'cost', 'price', 'account', 'expense', 'invoice'
    ],
    'Health': [
      'doctor', 'dentist', 'gym', 'workout', 'exercise', 'pill', 'pills', 'medicine',
      'hospital', 'clinic', 'health', 'sleep', 'run', 'walk', 'medication', 'vitamin'
    ],
    'Home': [
      'clean', 'fix', 'bulb', 'repair', 'car', 'door', 'wash', 'room', 'trash', 'plumber',
      'house', 'apartment', 'kitchen', 'bathroom', 'sink', 'leak', 'errand'
    ],
  };

  /// Suggests the best bucket for a thought, preferring existing buckets.
  static String suggestBucket(Map<String, dynamic> thought, List<String> existingBuckets) {
    final title = (thought['title'] as String? ?? '').toLowerCase();
    final content = (thought['content'] as String? ?? '').toLowerCase();
    final combined = "$title $content".trim();

    // 1. Check if any existing bucket matches directly
    for (final b in existingBuckets) {
      final bLower = b.trim().toLowerCase();
      if (bLower.isEmpty || bLower == 'general' || bLower == 'unsorted') continue;

      // Exact bucket name appears in text
      if (combined.contains(bLower)) {
        return b;
      }
      // Or any keyword from the category dictionary matches this existing bucket
      if (categoryKeywords.containsKey(b)) {
        final keywords = categoryKeywords[b]!;
        for (final kw in keywords) {
          if (_containsWord(combined, kw)) {
            return b;
          }
        }
      }
    }

    // 2. Check predefined semantic categories
    for (final entry in categoryKeywords.entries) {
      final catName = entry.key;
      final keywords = entry.value;

      for (final kw in keywords) {
        if (_containsWord(combined, kw)) {
          // If user has a bucket like "School related", prefer that over "School"
          final existingMatch = existingBuckets.firstWhere(
            (b) => b.toLowerCase().contains(catName.toLowerCase()),
            orElse: () => catName,
          );
          return existingMatch;
        }
      }
    }

    // 3. Fallback: If user has existing buckets, pick "General" or first
    final general = existingBuckets.firstWhere(
      (b) => b.toLowerCase() == 'general' || b.toLowerCase() == 'notes',
      orElse: () => 'General',
    );
    return general;
  }

  static bool _containsWord(String text, String word) {
    if (word.contains(' ') || word.contains('-')) {
      return text.contains(word);
    }
    final pattern = RegExp(r'\b' + RegExp.escape(word) + r'\b', caseSensitive: false);
    return pattern.hasMatch(text);
  }
}

/// Modal bottom sheet presenting suggestions in batches of 20 with group approval and undo.
class SuggestBucketsSheet extends StatefulWidget {
  const SuggestBucketsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SuggestBucketsSheet(),
    );
  }

  @override
  State<SuggestBucketsSheet> createState() => _SuggestBucketsSheetState();
}

class _SuggestBucketsSheetState extends State<SuggestBucketsSheet> {
  static const int _batchSize = 20;

  // Local overrides for suggested buckets: thoughtId -> chosenBucket
  final Map<String, String> _customSuggestions = {};
  final Set<String> _skippedThoughtIds = {};

  // For undo stack: list of {thoughtId, previousBucket, newBucket}
  final List<List<Map<String, dynamic>>> _undoHistory = [];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThoughtProvider>();

    // Active unsorted ideas
    final allUnsorted = provider.unsortedThoughts
        .where((t) => !_skippedThoughtIds.contains(t['id']))
        .toList();

    final totalCount = allUnsorted.length;
    final currentBatch = allUnsorted.take(_batchSize).toList();

    // Generate suggestions for this batch
    final existingBuckets = provider.bucketNames;
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final t in currentBatch) {
      final id = t['id'] as String;
      final bucket = _customSuggestions[id] ?? BucketClassifier.suggestBucket(t, existingBuckets);
      grouped.putIfAbsent(bucket, () => []).add(t);
    }

    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.90),
      decoration: const BoxDecoration(
        color: Color(0xFF1E222B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF333B48), width: 1.5)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            const SizedBox(height: 12),
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

            // Top Header: Title, Remaining count, Approve All
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFFFFD54F), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suggest Buckets',
                          style: appFont(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          totalCount > 0
                              ? 'Batch of ${currentBatch.length} ($totalCount unsorted remaining)'
                              : 'All caught up!',
                          style: appFont(color: const Color(0xFF9CA3AF), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (currentBatch.isNotEmpty)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD54F),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.done_all, size: 16),
                      label: Text(
                        'Approve all (${currentBatch.length})',
                        style: appFont(fontWeight: FontWeight.w900, fontSize: 12),
                      ),
                      onPressed: () => _approveBatch(context, currentBatch, grouped),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Divider(color: Color(0xFF333B48), height: 1),

            // Body: Grouped suggestions list
            Expanded(
              child: currentBatch.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle_outline, color: Color(0xFFFFD54F), size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'No more ideas in this batch!',
                              style: appFont(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'All unsorted thoughts have been reviewed.',
                              style: appFont(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      itemCount: grouped.keys.length,
                      itemBuilder: (context, groupIndex) {
                        final bucketName = grouped.keys.elementAt(groupIndex);
                        final thoughtsInGroup = grouped[bucketName]!;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF13151D),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF262C38)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Group Header: Suggested bucket name & Group Approve Button
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF1A1F29),
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.folder_outlined, color: Color(0xFFFFD54F), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Text(
                                            bucketName,
                                            style: appFont(
                                              color: const Color(0xFFFFD54F),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF262C38),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${thoughtsInGroup.length}',
                                              style: appFont(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(0xFFFFD54F),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: const Icon(Icons.check, size: 14),
                                      label: Text(
                                        'Approve group',
                                        style: appFont(fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                      onPressed: () => _approveGroup(context, bucketName, thoughtsInGroup),
                                    ),
                                  ],
                                ),
                              ),

                              // Thought rows in group
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: thoughtsInGroup.length,
                                separatorBuilder: (_, _) => const Divider(color: Color(0xFF262C38), height: 1),
                                itemBuilder: (context, idx) {
                                  final t = thoughtsInGroup[idx];
                                  final id = t['id'] as String;
                                  final title = TitleGenerator.getIdeaName(t);
                                  final content = t['content'] as String? ?? '';

                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: appFont(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (content.isNotEmpty && content != title)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              content,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: appFont(color: const Color(0xFF9CA3AF), fontSize: 11),
                                            ),
                                          ),
                                        const SizedBox(height: 8),

                                        // Action buttons: Approve, Change, Skip (Requirement 4)
                                        Row(
                                          children: [
                                            // 1. Approve
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFFFFD54F),
                                                foregroundColor: Colors.black,
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                minimumSize: const Size(60, 28),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              ),
                                              onPressed: () => _approveThought(context, t, bucketName),
                                              child: Text('Approve', style: appFont(fontWeight: FontWeight.bold, fontSize: 11)),
                                            ),
                                            const SizedBox(width: 8),

                                            // 2. Change (pick or create bucket)
                                            OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.white,
                                                side: const BorderSide(color: Color(0xFF333B48)),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                minimumSize: const Size(60, 28),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              ),
                                              onPressed: () => _changeBucket(context, t),
                                              child: Text('Change', style: appFont(fontSize: 11)),
                                            ),
                                            const SizedBox(width: 8),

                                            // 3. Skip
                                            TextButton(
                                              style: TextButton.styleFrom(
                                                foregroundColor: const Color(0xFF9CA3AF),
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                minimumSize: const Size(40, 28),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  _skippedThoughtIds.add(id);
                                                });
                                              },
                                              child: Text('Skip', style: appFont(fontSize: 11)),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Bottom Footer with Undo if changes were made
            if (_undoHistory.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF13151D),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_undoHistory.last.length} thoughts moved',
                      style: appFont(color: const Color(0xFF9CA3AF), fontSize: 12),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFFFD54F)),
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('Undo last action'),
                      onPressed: () => _undoLastAction(context),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveThought(BuildContext context, Map<String, dynamic> thought, String bucket) async {
    final provider = context.read<ThoughtProvider>();
    final id = thought['id'] as String;

    // Record undo
    _undoHistory.add([
      {'id': id, 'previous_bucket': thought['bucket'], 'title': TitleGenerator.getIdeaName(thought)}
    ]);

    await provider.addBucket(bucket);
    await provider.fileThought(id, bucket);

    if (mounted) {
      AppToast.show(context, message: 'Moved into "$bucket"');
      setState(() {});
    }
  }

  Future<void> _approveGroup(BuildContext context, String bucket, List<Map<String, dynamic>> thoughts) async {
    final provider = context.read<ThoughtProvider>();
    final undoBatch = <Map<String, dynamic>>[];

    await provider.addBucket(bucket);
    for (final t in thoughts) {
      final id = t['id'] as String;
      undoBatch.add({'id': id, 'previous_bucket': t['bucket']});
      await provider.fileThought(id, bucket);
    }

    _undoHistory.add(undoBatch);

    if (mounted) {
      AppToast.show(context, message: 'Moved ${thoughts.length} thoughts into "$bucket"');
      setState(() {});
    }
  }

  Future<void> _approveBatch(BuildContext context, List<Map<String, dynamic>> currentBatch, Map<String, List<Map<String, dynamic>>> grouped) async {
    final provider = context.read<ThoughtProvider>();
    final undoBatch = <Map<String, dynamic>>[];

    for (final entry in grouped.entries) {
      final bucket = entry.key;
      final thoughts = entry.value;
      await provider.addBucket(bucket);
      for (final t in thoughts) {
        final id = t['id'] as String;
        undoBatch.add({'id': id, 'previous_bucket': t['bucket']});
        await provider.fileThought(id, bucket);
      }
    }

    _undoHistory.add(undoBatch);

    if (mounted) {
      AppToast.show(
        context,
        message: 'Moved ${currentBatch.length} thoughts into ${grouped.keys.length} buckets',
      );
      setState(() {});
    }
  }

  Future<void> _undoLastAction(BuildContext context) async {
    if (_undoHistory.isEmpty) return;
    final provider = context.read<ThoughtProvider>();
    final lastBatch = _undoHistory.removeLast();

    for (final item in lastBatch) {
      final id = item['id'] as String;
      final prevBucket = item['previous_bucket'] as String?;
      await provider.fileThought(id, prevBucket ?? '');
    }

    if (mounted) {
      AppToast.show(context, message: 'Undid move of ${lastBatch.length} thoughts back to Unsorted');
      setState(() {});
    }
  }

  void _changeBucket(BuildContext context, Map<String, dynamic> thought) async {
    final provider = context.read<ThoughtProvider>();
    final buckets = provider.bucketNames;
    final newBucketCtrl = TextEditingController();

    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333B48)),
        ),
        title: Text(
          'Choose or Create Bucket',
          style: appFont(color: const Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: newBucketCtrl,
                style: appFont(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'New bucket name...',
                  hintStyle: appFont(color: Colors.grey),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: const Color(0xFF13151D),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF333B48)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add, color: Color(0xFFFFD54F)),
                    onPressed: () {
                      final name = newBucketCtrl.text.trim();
                      if (name.isNotEmpty) Navigator.pop(ctx, name);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Existing buckets:',
                style: appFont(color: const Color(0xFF9CA3AF), fontSize: 12),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: buckets.map((b) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_outlined, color: Color(0xFFFFD54F), size: 18),
                        title: Text(b, style: appFont(color: Colors.white, fontSize: 13)),
                        onTap: () => Navigator.pop(ctx, b),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );

    if (chosen != null && chosen.trim().isNotEmpty) {
      setState(() {
        _customSuggestions[thought['id'] as String] = chosen.trim();
      });
    }
  }
}
