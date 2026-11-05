import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../settings_service.dart';

/// A keyboard-safe bottom sheet and dialog container that keeps a constant opening height,
/// moves directly above the keyboard without covering it, trims to available free space
/// on small screens, and provides smooth sliding animations (<=180ms, disabled when reduced motion is on).
class KeyboardSafeSheet extends StatefulWidget {
  static const Key containerKey = Key('keyboard_safe_sheet_container');

  final Widget? header;
  final Widget? pinnedHeader;
  final Widget? pinnedFooter;
  final Widget child;
  final double openingHeight;
  final Color? backgroundColor;
  final BorderRadiusGeometry? borderRadius;
  final EdgeInsetsGeometry padding;
  final BoxBorder? border;
  final bool isDialog;
  final double maxWidth;

  const KeyboardSafeSheet({
    super.key,
    this.header,
    this.pinnedHeader,
    this.pinnedFooter,
    required this.child,
    this.openingHeight = 474.0,
    this.backgroundColor,
    this.borderRadius,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    this.border,
    this.isDialog = false,
    this.maxWidth = 480.0,
  });

  /// Helper to format idea heading according to strict Part 1 Rule 7:
  /// Adding "`<idea name>`" to... on ONE line, cut with an ellipsis.
  /// Use the idea's title if it contains at least one letter or digit;
  /// otherwise the first 40 characters of the text, cut at a word boundary;
  /// if there is no text: "Empty idea". Never show "".
  static String formatIdeaHeading(Map<String, dynamic> idea) {
    final title = (idea['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty && RegExp(r'[a-zA-Z0-9]').hasMatch(title)) {
      return title;
    }
    final content = (idea['content'] as String?)?.trim() ?? '';
    if (content.isEmpty) {
      return 'Empty idea';
    }
    if (content.length <= 40) {
      return content;
    }
    String cut = content.substring(0, 40);
    final lastSpace = cut.lastIndexOf(' ');
    if (lastSpace > 0) {
      cut = cut.substring(0, lastSpace);
    }
    cut = cut.trim();
    return cut.isNotEmpty ? cut : 'Empty idea';
  }

  /// Reusable helper to show a keyboard-safe bottom sheet with isScrollControlled: true and useSafeArea: true.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    Color? barrierColor,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: barrierColor,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: builder,
    );
  }

  @override
  State<KeyboardSafeSheet> createState() => _KeyboardSafeSheetState();
}

class _KeyboardSafeSheetState extends State<KeyboardSafeSheet> {
  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final statusBarHeight = mediaQuery.padding.top;
    final keyboardHeight = mediaQuery.viewInsets.bottom;

    SettingsService? settings;
    try {
      settings = context.watch<SettingsService>();
    } catch (_) {}

    // Reduced motion check (system setting or settings)
    final bool isReducedMotion =
        MediaQuery.maybeDisableAnimationsOf(context) ?? mediaQuery.disableAnimations;
    final Duration animDuration = isReducedMotion
        ? Duration.zero
        : const Duration(milliseconds: 180);

    // Free space: screen height minus keyboard height minus status bar minus 12px gap
    final double freeSpace = screenHeight - keyboardHeight - statusBarHeight - 12.0;

    // Target height: maintain opening height, but trim to free space if screen is too small
    final double targetHeight = (freeSpace > 0 && widget.openingHeight > freeSpace)
        ? freeSpace
        : widget.openingHeight;

    AppColors colors;
    if (settings != null) {
      colors = AppColors.of(settings.theme);
    } else {
      colors = AppColors.dark;
    }

    final effectiveBg = widget.backgroundColor ?? colors.bg;
    final effectiveBorder = widget.border ?? Border.all(color: colors.line);
    final effectiveRadius = widget.borderRadius ??
        (widget.isDialog
            ? BorderRadius.circular(20)
            : const BorderRadius.vertical(top: Radius.circular(22)));

    Widget sheetBody = Container(
      key: KeyboardSafeSheet.containerKey,
      constraints: BoxConstraints(
        minHeight: widget.isDialog ? 0 : targetHeight,
        maxHeight: targetHeight,
        maxWidth: widget.isDialog ? widget.maxWidth : double.infinity,
      ),
      padding: widget.padding,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: effectiveRadius,
        border: effectiveBorder,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.header != null) widget.header!,
          if (widget.pinnedHeader != null) widget.pinnedHeader!,
          if (widget.isDialog)
            Flexible(child: widget.child)
          else
            Expanded(child: widget.child),
          if (widget.pinnedFooter != null) widget.pinnedFooter!,
        ],
      ),
    );

    if (widget.isDialog) {
      return AnimatedPadding(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        duration: animDuration,
        curve: Curves.easeOutQuad,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: sheetBody,
          ),
        ),
      );
    }

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      duration: animDuration,
      curve: Curves.easeOutQuad,
      child: sheetBody,
    );
  }
}
