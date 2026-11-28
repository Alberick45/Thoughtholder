import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';
import '../thought_provider.dart';
import '../starter_buckets_screen.dart';
import '../history_screen.dart';
import '../duplicate_finder_screen.dart';
import 'group_page_scaffold.dart';
import 'settings_state.dart';
import 'settings_widgets.dart';
import 'create_bucket_sheet.dart';

class IdeasGroupScreen extends StatelessWidget {
  const IdeasGroupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const GroupPageScaffold(
      title: 'Ideas and buckets',
      child: IdeasGroupContent(),
    );
  }
}

class IdeasGroupContent extends StatefulWidget {
  const IdeasGroupContent({super.key});

  @override
  State<IdeasGroupContent> createState() => _IdeasGroupContentState();
}

class _IdeasGroupContentState extends State<IdeasGroupContent> {
  static const String _groupId = 'ideas_group';

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final thoughtProvider = context.watch<ThoughtProvider>();
    final colors = AppColors.of(settings.theme);
    final isExpanded = SettingsState.isExpanded(_groupId);

    final finishedCount = thoughtProvider.doneCount;
    final finishedText = '$finishedCount finished idea${finishedCount == 1 ? '' : 's'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Unsorted order
        Text(
          'Unsorted order',
          style: appFont(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Choose whether newest or oldest ideas appear first in Unsorted.',
          style: appFont(color: colors.mute, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _buildOption(
              label: 'Newest first (default)',
              isSelected: settings.unsortedOrder == 'newest',
              onTap: () => settings.setUnsortedOrder('newest'),
              colors: colors,
            ),
            const SizedBox(width: 8),
            _buildOption(
              label: 'Oldest first',
              isSelected: settings.unsortedOrder == 'oldest',
              onTap: () => settings.setUnsortedOrder('oldest'),
              colors: colors,
            ),
          ],
        ),

        const SizedBox(height: 20),
        Divider(color: colors.line, height: 1),
        const SizedBox(height: 16),

        // 2. Bucket order in Sorted
        Text(
          'Sorted bucket order',
          style: appFont(
            color: colors.text,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Order buckets by number of ideas, creation, or alphabetically.',
          style: appFont(color: colors.mute, fontSize: 13),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildOption(
              label: 'Most ideas first',
              isSelected: settings.bucketOrder == 'ideas',
              onTap: () => settings.setBucketOrder('ideas'),
              colors: colors,
            ),
            _buildOption(
              label: 'Creation order',
              isSelected: settings.bucketOrder == 'creation',
              onTap: () => settings.setBucketOrder('creation'),
              colors: colors,
            ),
            _buildOption(
              label: 'Alphabetical',
              isSelected: settings.bucketOrder == 'alphabetical',
              onTap: () => settings.setBucketOrder('alphabetical'),
              colors: colors,
            ),
          ],
        ),

        const SizedBox(height: 20),
        Divider(color: colors.line, height: 1),
        const SizedBox(height: 16),

        // 3. History row
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              children: [
                Icon(Icons.history, color: colors.gold, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'History',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        finishedText,
                        style: appFont(color: colors.mute, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.mute, size: 20),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 4. Find duplicates row
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DuplicateFinderScreen()),
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              children: [
                Icon(Icons.copy_all_outlined, color: colors.gold, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find duplicates',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Review and merge ideas with identical text',
                        style: appFont(color: colors.mute, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.mute, size: 20),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 5. Make a new bucket row
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await showCreateBucketSheet(context, thoughtProvider, colors);
            if (mounted) setState(() {});
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            child: Row(
              children: [
                Icon(Icons.add_circle_outline, color: colors.gold, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Make a new bucket',
                        style: appFont(
                          color: colors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Create a custom bucket with a name and icon',
                        style: appFont(color: colors.mute, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.mute, size: 20),
              ],
            ),
          ),
        ),

        // 6. Collapsible Starter buckets (under "Show more options")
        if (isExpanded) ...[
          const SizedBox(height: 20),
          Divider(color: colors.line, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Starter buckets',
                      style: appFont(
                        color: colors.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add any of the standard starter buckets anytime.',
                      style: appFont(color: colors.mute, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await showCreateBucketSheet(
                      context, thoughtProvider, colors);
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New bucket'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.gold,
                  side: BorderSide(color: colors.gold),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...kStarterBuckets.map((starter) {
            final name = starter.name;
            final iconKey = starter.iconKey;
            final desc = starter.description;
            final iconData = kBucketIcons[iconKey] ?? Icons.folder_outlined;
            final bool isExisting = thoughtProvider.buckets.any((b) =>
                (b['name'] as String).trim().toLowerCase() ==
                name.trim().toLowerCase());

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.line),
                    ),
                    child: Icon(iconData, color: colors.gold, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: appFont(
                            color: colors.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          style: appFont(color: colors.mute, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isExisting)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.line),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, size: 14, color: colors.done),
                          const SizedBox(width: 4),
                          Text(
                            'Added',
                            style: appFont(color: colors.mute, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  else
                    SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await thoughtProvider.addBucket(name, icon: iconKey);
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.gold,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],

        const SizedBox(height: 12),
        ShowMoreButton(
          count: 1,
          isExpanded: isExpanded,
          onTap: () {
            setState(() {
              SettingsState.toggleExpanded(_groupId);
            });
          },
          colors: colors,
        ),
      ],
    );
  }

  Widget _buildOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required AppColors colors,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? colors.goldBg : colors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? colors.gold : colors.line,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: appFont(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colors.gold : colors.mute,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
