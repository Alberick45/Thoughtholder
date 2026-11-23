import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../thought_provider.dart';

/// A bucket selector for Add/Edit Sticky Note flows.
///
/// Lists existing buckets (chips), defaults to "Raw", provides a "+ New bucket"
/// option that opens a small text input, and supports optional filtering by typing
/// without requiring typing.
class StickyNoteBucketPicker extends StatefulWidget {
  final String? initialBucket;
  final ValueChanged<String> onBucketChanged;

  const StickyNoteBucketPicker({
    super.key,
    this.initialBucket,
    required this.onBucketChanged,
  });

  @override
  State<StickyNoteBucketPicker> createState() => _StickyNoteBucketPickerState();
}

class _StickyNoteBucketPickerState extends State<StickyNoteBucketPicker> {
  late String _selectedBucket;
  final Set<String> _customBuckets = {};
  bool _showNewBucketInput = false;
  final TextEditingController _filterCtrl = TextEditingController();
  final TextEditingController _newBucketCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialBucket?.trim();
    _selectedBucket = (initial != null && initial.isNotEmpty) ? initial : 'Raw';
    // Inform parent of initial default selection
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onBucketChanged(_selectedBucket);
      }
    });
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    _newBucketCtrl.dispose();
    super.dispose();
  }

  void _selectBucket(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _selectedBucket = trimmed;
      _showNewBucketInput = false;
    });
    widget.onBucketChanged(trimmed);
  }

  void _submitNewBucket() {
    final name = _newBucketCtrl.text.trim();
    if (name.isNotEmpty) {
      _customBuckets.add(name);
      _selectBucket(name);
      _newBucketCtrl.clear();
    } else {
      setState(() {
        _showNewBucketInput = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ThoughtProvider>();
    final existingBuckets = provider.bucketNames;

    // Gather distinct buckets, ensuring 'Raw' is at the top
    final allBuckets = <String>{'Raw'};
    allBuckets.addAll(existingBuckets.where((b) => b.trim().isNotEmpty));
    allBuckets.addAll(_customBuckets);
    if (_selectedBucket.isNotEmpty) {
      allBuckets.add(_selectedBucket);
    }

    final query = _filterCtrl.text.trim().toLowerCase();
    final filteredBuckets = query.isEmpty
        ? allBuckets.toList()
        : allBuckets.where((b) => b.toLowerCase().contains(query)).toList();

    final hasExactMatch = allBuckets.any((b) => b.trim().toLowerCase() == query);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Bucket',
              style: appFont(
                color: Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD54F).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.4)),
              ),
              child: Text(
                _selectedBucket,
                style: appFont(
                  color: const Color(0xFFFFD54F),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Optional filter text field (typing filters, but is NOT required)
        if (allBuckets.length > 3 || _filterCtrl.text.isNotEmpty) ...[
          TextField(
            controller: _filterCtrl,
            style: appFont(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              hintText: 'Filter buckets or type new...',
              hintStyle: appFont(color: Colors.grey, fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 16, color: Colors.grey),
              suffixIcon: _filterCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: Colors.grey),
                      onPressed: () {
                        _filterCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF333B48)),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
        ],

        // Bucket chips
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 130),
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...filteredBuckets.map((bucketName) {
                  final isSelected =
                      _selectedBucket.trim().toLowerCase() == bucketName.trim().toLowerCase();
                  return ChoiceChip(
                    key: Key('bucket_chip_$bucketName'),
                    label: Text(
                      bucketName,
                      style: appFont(
                        color: isSelected ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: const Color(0xFFFFD54F),
                    backgroundColor: const Color(0xFF262C36),
                    side: BorderSide(
                      color: isSelected ? const Color(0xFFFFD54F) : const Color(0xFF333B48),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    onSelected: (selected) {
                      if (selected) {
                        _selectBucket(bucketName);
                      }
                    },
                  );
                }),

                // "+ Create <query>" chip if user typed a non-matching name
                if (query.isNotEmpty && !hasExactMatch)
                  ActionChip(
                    key: const Key('bucket_chip_create_query'),
                    avatar: const Icon(Icons.add, size: 14, color: Color(0xFFFFD54F)),
                    label: Text(
                      '+ Create "${_filterCtrl.text.trim()}"',
                      style: appFont(color: const Color(0xFFFFD54F), fontSize: 12),
                    ),
                    backgroundColor: const Color(0xFF262C36),
                    side: const BorderSide(color: Color(0xFFFFD54F)),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    onPressed: () {
                      final name = _filterCtrl.text.trim();
                      _customBuckets.add(name);
                      _selectBucket(name);
                      _filterCtrl.clear();
                    },
                  ),

                // "+ New bucket" action chip
                if (!_showNewBucketInput)
                  ActionChip(
                    key: const Key('bucket_chip_new'),
                    avatar: const Icon(Icons.add, size: 14, color: Color(0xFFFFD54F)),
                    label: Text(
                      '+ New bucket',
                      style: appFont(
                        color: const Color(0xFFFFD54F),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: const Color(0xFF262C36),
                    side: const BorderSide(color: Color(0xFF333B48)),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    onPressed: () {
                      setState(() {
                        _showNewBucketInput = true;
                      });
                    },
                  ),
              ],
            ),
          ),
        ),

        // Inline input revealed when "+ New bucket" is tapped
        if (_showNewBucketInput) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('new_bucket_input_field'),
                  controller: _newBucketCtrl,
                  autofocus: true,
                  style: appFont(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    hintText: 'Enter new bucket name...',
                    hintStyle: appFont(color: Colors.grey, fontSize: 12),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF333B48)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFFFD54F)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: (_) => _submitNewBucket(),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const Key('new_bucket_confirm_btn'),
                icon: const Icon(Icons.check, color: Color(0xFFFFD54F), size: 20),
                tooltip: 'Add bucket',
                onPressed: _submitNewBucket,
              ),
              IconButton(
                key: const Key('new_bucket_cancel_btn'),
                icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                tooltip: 'Cancel',
                onPressed: () {
                  setState(() {
                    _showNewBucketInput = false;
                  });
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}
