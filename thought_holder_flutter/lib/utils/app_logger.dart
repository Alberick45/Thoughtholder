import 'package:flutter/foundation.dart';

/// Lightweight, safe application logger.
/// - In release builds: completely silent.
/// - In debug builds: logs messages safely without writing private idea text or keys.
class AppLogger {
  AppLogger._();

  static void info(String tag, String message) {
    if (kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  static void error(String tag, String message, [dynamic error]) {
    if (kDebugMode) {
      if (error != null) {
        // Sanitize error: keep only the top-level exception type/message without potential query or payload dumps
        final errStr = error.toString().split('\n').first;
        debugPrint('[$tag] ERROR: $message ($errStr)');
      } else {
        debugPrint('[$tag] ERROR: $message');
      }
    }
  }
}
