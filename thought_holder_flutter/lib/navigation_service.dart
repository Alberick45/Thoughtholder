import 'package:flutter/material.dart';

class NavigationNotifier extends ChangeNotifier {
  int _mainTabIndex = 1; // Default to Stream tab to show Stream view immediately
  String _streamSubTab = 'unsorted'; // 'unsorted' | 'sorted' | 'done'
  bool _isTrashOpen = false;
  String? _selectedBucket;

  int get mainTabIndex => _mainTabIndex;
  String get streamSubTab => _streamSubTab;
  bool get isTrashOpen => _isTrashOpen;
  String? get selectedBucket => _selectedBucket;

  void setMainTab(int index) {
    if (_mainTabIndex != index) {
      _mainTabIndex = index;
      if (index == 1) {
        // Tapping Stream returns from Trash to Stream
        _isTrashOpen = false;
      }
      notifyListeners();
    } else if (index == 1 && _isTrashOpen) {
      // Tapping Stream while already on Stream but Trash is open closes Trash
      _isTrashOpen = false;
      notifyListeners();
    }
  }

  void goToStream({String subTab = 'unsorted'}) {
    _mainTabIndex = 1;
    _streamSubTab = subTab;
    _isTrashOpen = false;
    _selectedBucket = null;
    notifyListeners();
  }

  void goToCapture() {
    _mainTabIndex = 0;
    notifyListeners();
  }

  void setStreamSubTab(String subTab) {
    _streamSubTab = subTab;
    _isTrashOpen = false;
    _selectedBucket = null;
    notifyListeners();
  }

  void toggleTrash() {
    _isTrashOpen = !_isTrashOpen;
    notifyListeners();
  }

  void closeTrash() {
    if (_isTrashOpen) {
      _isTrashOpen = false;
      notifyListeners();
    }
  }

  void selectBucket(String? bucket) {
    _selectedBucket = bucket;
    notifyListeners();
  }
}
