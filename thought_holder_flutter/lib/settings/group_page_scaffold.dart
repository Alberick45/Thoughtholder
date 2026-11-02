import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';

/// Full-screen wrapper for a Settings Group page with "‹ All settings" back button
/// and controls wrapped inside a single clean theme card.
class GroupPageScaffold extends StatelessWidget {
  final String title;
  final Widget child;

  const GroupPageScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final colors = AppColors.of(settings.theme);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 140,
        leading: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Navigator.pop(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_new, size: 16, color: colors.gold),
                const SizedBox(width: 6),
                Text(
                  'All settings',
                  style: appFont(
                    color: colors.gold,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        title: Text(
          title,
          style: appFont(
            color: colors.text,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.line),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
