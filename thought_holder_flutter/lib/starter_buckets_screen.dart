import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_theme.dart';
import 'settings_service.dart';
import 'thought_provider.dart';

class StarterBucketItem {
  final String name;
  final String iconKey;
  final String description;
  final bool defaultChecked;

  const StarterBucketItem({
    required this.name,
    required this.iconKey,
    required this.description,
    this.defaultChecked = false,
  });
}

const List<StarterBucketItem> kStarterBuckets = [
  StarterBucketItem(
    name: 'Tasks',
    iconKey: 'briefcase',
    description: 'Things you need to do',
    defaultChecked: true,
  ),
  StarterBucketItem(
    name: 'Personal improvement',
    iconKey: 'heart',
    description: 'Habits, skills and ways to grow',
    defaultChecked: true,
  ),
  StarterBucketItem(
    name: 'Projects',
    iconKey: 'bulb',
    description: 'Things you are building or planning',
    defaultChecked: false,
  ),
  StarterBucketItem(
    name: 'Learning',
    iconKey: 'book',
    description: 'School, courses and things to study',
    defaultChecked: false,
  ),
  StarterBucketItem(
    name: 'Someday',
    iconKey: 'star',
    description: 'Ideas you want to keep but not do yet',
    defaultChecked: false,
  ),
];

class StarterBucketsScreen extends StatefulWidget {
  const StarterBucketsScreen({super.key});

  @override
  State<StarterBucketsScreen> createState() => _StarterBucketsScreenState();
}

class _StarterBucketsScreenState extends State<StarterBucketsScreen> {
  late final Set<int> _selectedIndices;

  @override
  void initState() {
    super.initState();
    _selectedIndices = {
      for (int i = 0; i < kStarterBuckets.length; i++)
        if (kStarterBuckets[i].defaultChecked) i
    };
  }

  Future<void> _onUseThese() async {
    final provider = context.read<ThoughtProvider>();
    final settings = context.read<SettingsService>();

    for (final index in _selectedIndices) {
      final item = kStarterBuckets[index];
      await provider.addBucket(item.name, icon: item.iconKey);
    }
    await settings.setHasChosenStarterBuckets(true);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onStartEmpty() async {
    final settings = context.read<SettingsService>();
    await settings.setHasChosenStarterBuckets(true);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // Heading
              Text(
                'Pick your starter buckets',
                style: appFont(
                  color: colors.text,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              // Subtitle
              Text(
                'Buckets are where your ideas live. You can rename, delete or add more any time.',
                style: appFont(
                  color: colors.mute,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Big, tappable rows (>= 56px each)
              Expanded(
                child: ListView.separated(
                  itemCount: kStarterBuckets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (ctx, index) {
                    final item = kStarterBuckets[index];
                    final isChecked = _selectedIndices.contains(index);
                    final iconData = getBucketIcon(item.iconKey);

                    return Semantics(
                      button: true,
                      checked: isChecked,
                      label: '${item.name}: ${item.description}',
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            if (isChecked) {
                              _selectedIndices.remove(index);
                            } else {
                              _selectedIndices.add(index);
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 56),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isChecked ? colors.goldBg : colors.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isChecked ? colors.gold : colors.line,
                              width: isChecked ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Checkbox
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: Checkbox(
                                  value: isChecked,
                                  activeColor: colors.gold,
                                  checkColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  side: BorderSide(
                                    color: isChecked ? colors.gold : colors.mute,
                                    width: 1.5,
                                  ),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedIndices.add(index);
                                      } else {
                                        _selectedIndices.remove(index);
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Icon
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isChecked ? colors.gold : colors.bg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  iconData,
                                  size: 20,
                                  color: isChecked ? Colors.black : colors.gold,
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Name + Description
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      item.name,
                                      style: appFont(
                                        color: colors.text,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.description,
                                      style: appFont(
                                        color: colors.mute,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Bottom buttons: "Use these" (gold, primary) and "Start empty"
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _onUseThese,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.gold,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Use these',
                    style: appFont(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: TextButton(
                  onPressed: _onStartEmpty,
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    'Start empty',
                    style: appFont(
                      color: colors.mute,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
