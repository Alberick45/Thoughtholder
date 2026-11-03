import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app_logger.dart';

class GlobalErrorHandler {
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static DateTime _lastErrorNotification = DateTime.fromMillisecondsSinceEpoch(0);

  /// Initializes global exception catching.
  /// Unexpected errors are safely recorded without logging user ideas or secret keys,
  /// and a calm, reassuring message is presented so the app never terminates or loses text.
  static void init() {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        debugPrint('[FlutterError] ${details.exceptionAsString()}\n${details.stack}');
      } else {
        AppLogger.error('GlobalErrorHandler', 'Flutter framework error');
      }
      _notifyUser();
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      if (kDebugMode) {
        debugPrint('[PlatformError] $error\n$stack');
      } else {
        AppLogger.error('GlobalErrorHandler', 'Platform asynchronous error');
      }
      _notifyUser();
      return true; // Mark as handled to prevent process termination
    };
  }

  static void _notifyUser() {
    final now = DateTime.now();
    // Throttled to at most once per minute (60 seconds) so user is never spammed
    if (now.difference(_lastErrorNotification).inSeconds < 60) return;
    _lastErrorNotification = now;

    final state = messengerKey.currentState;
    if (state != null) {
      state.removeCurrentSnackBar();
      state.showSnackBar(
        const SnackBar(
          content: Text(
            'Something unexpected happened, but your ideas and typed text are safe.',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
