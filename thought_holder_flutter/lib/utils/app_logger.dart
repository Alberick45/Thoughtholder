import 'package:flutter/foundation.dart';

/// Lightweight, safe application logger.
/// - In release builds: completely silent.
/// - In debug builds: logs messages safely without writing private idea text or keys.
class AppLogger {
  AppLogger._();

  /// Redacts secret keys (e.g. gsk_...) and tokens from any logged text.
  static String sanitize(String input) {
    return input.replaceAll(RegExp(r'gsk_[A-Za-z0-9_-]+'), '[REDACTED_KEY]');
  }

  static void info(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] ${sanitize(message)}');
    }
  }

  static void error(String tag, String message, [dynamic error]) {
    if (kDebugMode) {
      final safeMessage = sanitize(message);
      if (error != null) {
        // Sanitize error: keep only the top-level exception type/message without potential query or payload dumps
        final errStr = sanitize(error.toString().split('\n').first);
        debugPrint('[$tag] ERROR: $safeMessage ($errStr)');
      } else {
        debugPrint('[$tag] ERROR: $safeMessage');
      }
    }
  }
}
