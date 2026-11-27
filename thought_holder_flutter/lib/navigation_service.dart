import 'package:flutter/material.dart';

class NavigationNotifier extends ChangeNotifier {
  int _mainTabIndex = 0; // Open app in Capture
  String _streamSubTab = 'sorted'; // When switching to Stream, Sorted is active
  bool _isTrashOpen = false;
  String? _selectedBucket;
  bool _isBoardExpanded = true; // Board tab defaults to full sticky note board

  int get mainTabIndex => _mainTabIndex;
  String get streamSubTab => _streamSubTab;
  bool get isTrashOpen => _isTrashOpen;
  String? get selectedBucket => _selectedBucket;
  bool get isBoardExpanded => _isBoardExpanded;

  void setBoardExpanded(bool expanded) {
    if (_isBoardExpanded != expanded) {
      _isBoardExpanded = expanded;
      notifyListeners();
    }
  }

  void toggleBoardExpanded() {
    _isBoardExpanded = !_isBoardExpanded;
    notifyListeners();
  }

  void setMainTab(int index) {
    if (_mainTabIndex != index) {
      _mainTabIndex = index;
      if (index == 1) {
        _isBoardExpanded = true;
        _streamSubTab = 'sorted';
        _selectedBucket = null;
        _isTrashOpen = false;
      }
      notifyListeners();
    } else if (index == 1) {
      if (_isTrashOpen) {
        _isTrashOpen = false;
        _isBoardExpanded = true;
        _streamSubTab = 'sorted';
        _selectedBucket = null;
        notifyListeners();
      } else if (!_isBoardExpanded) {
        // Tapping Board tab while inside Sort returns to the Board
        _isBoardExpanded = true;
        notifyListeners();
      }
    }
  }

  void goToStream({String subTab = 'unsorted'}) {
    _mainTabIndex = 1;
    _streamSubTab = subTab;
    _isTrashOpen = false;
    _selectedBucket = null;
    _isBoardExpanded = false; // Opens Sort / Stream list
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
