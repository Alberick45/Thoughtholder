import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'settings_service.dart';
import 'thought_provider.dart';
import 'ble_merge_engine.dart';

class DuplicateFinderScreen extends StatefulWidget {
  const DuplicateFinderScreen({super.key});

  @override
  State<DuplicateFinderScreen> createState() => _DuplicateFinderScreenState();
}

class _DuplicateFinderScreenState extends State<DuplicateFinderScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final provider = context.watch<ThoughtProvider>();
    final colors = AppColors.of(settings.theme);

    final duplicateGroups = BleMergeEngine.findExactTextDuplicates(provider.thoughts);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        title: Text(
          'Find duplicates',
          style: appFont(color: colors.text, fontWeight: FontWeight.bold),
        ),
        backgroundColor: colors.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.gold),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Review ideas with identical text. Choose "Merge" to keep one and safely remove the other.',
                style: appFont(color: colors.mute, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: duplicateGroups.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline, size: 56, color: colors.done),
                            const SizedBox(height: 12),
                            Text(
                              'No duplicate ideas found',
                              style: appFont(
                                color: colors.text,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Your ideas are clean and tidy.',
                              style: appFont(color: colors.mute, fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: duplicateGroups.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 16),
                        itemBuilder: (ctx, index) {
                          final group = duplicateGroups[index];
                          final sample = group.first;
                          final text = sample['content'] as String? ?? '';
                          final count = group.length;

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colors.line),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: colors.goldBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '$count copies',
                                        style: appFont(
                                          color: colors.gold,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      group.map((t) => t['thought_id'] ?? 'LOG').join(', '),
                                      style: appFont(color: colors.mute, fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  text,
                                  style: appFont(
                                    color: colors.text,
                                    fontSize: 15,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final keep = group.first;
                                      final dupIds = group.skip(1).map((t) => t['id'] as String).toList();
                                      await provider.mergeDuplicates(keep['id'] as String, dupIds);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Merged into ${keep['thought_id']}'),
                                            backgroundColor: const Color(0xFF141416),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(Icons.merge, color: Colors.black, size: 18),
                                    label: Text(
                                      'Merge (keep 1 copy)',
                                      style: appFont(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
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
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
