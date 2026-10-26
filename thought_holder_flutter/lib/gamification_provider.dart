import 'package:flutter/material.dart';

class GamificationProvider with ChangeNotifier {
  int _xp = 0;
  int _streak = 1;
  int _lastCaptureTime = DateTime.now().millisecondsSinceEpoch;

  int get xp => _xp;
  int get streak => _streak;
  int get level => (_xp ~/ 100) + 1;
  int get xpInLevel => _xp % 100;

  void addXp(int amount) {
    _xp += amount;
    
    // Check streak
    final now = DateTime.now();
    final lastCapture = DateTime.fromMillisecondsSinceEpoch(_lastCaptureTime);
    final difference = now.difference(lastCapture).inDays;
    
    if (difference == 1) {
      _streak++;
    } else if (difference > 1) {
      _streak = 1;
    }
    
    _lastCaptureTime = now.millisecondsSinceEpoch;
    notifyListeners();
  }

  void captureVoice() => addXp(15);
  void captureText() => addXp(10);
  void completeTask() => addXp(20);
}
