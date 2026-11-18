import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_theme.dart';

/// Standard App Notification / Toast message box
/// - Positioned in the bottom-left
/// - Compact width (~380px on desktop)
/// - Short duration (~2.8s instead of 6s to avoid nuisance)
/// - Dedicated [X] close button for instant dismissal
/// - Optional [UNDO] or action button
class AppToast {
  static void show(
    BuildContext context, {
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 2800),
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    final screenWidth = MediaQuery.of(context).size.width;
    final targetWidth = math.min(screenWidth * 0.88, 380.0);
    final rightMargin = math.max(16.0, screenWidth - targetWidth - 16.0);

    messenger.showSnackBar(
      SnackBar(
        elevation: 8,
        backgroundColor: const Color(0xFF1E222B),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        margin: EdgeInsets.only(bottom: 80, left: 16, right: rightMargin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF333B48), width: 1.2),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        content: Row(
          children: [
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: appFont(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  onAction();
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    actionLabel,
                    style: appFont(
                      color: const Color(0xFFFFD54F),
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            InkWell(
              onTap: () => messenger.hideCurrentSnackBar(),
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: Color(0xFF9CA3AF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

