import 'package:flutter/material.dart';
import 'database_helper.dart';

class ThoughtProvider with ChangeNotifier {
  List<Map<String, dynamic>> _thoughts = [];
  
  List<Map<String, dynamic>> get thoughts => _thoughts;

  ThoughtProvider() {
    loadThoughts();
  }

  Future<void> loadThoughts() async {
    _thoughts = await DatabaseHelper.instance.fetchAllThoughts();
    notifyListeners();
  }

  Future<void> addThought(String content, String type, {String tags = ''}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final thought = {
      'id': UniqueKey().toString(),
      'thought_id': 'LOG-${now % 10000}',
      'content': content,
      'type': type,
      'status': 'active',
      'tags': tags,
      'summary': '',
      'created_at': now,
      'last_viewed_at': now,
      'stale_score': 0,
      'linked_thoughts': '[]'
    };
    
    await DatabaseHelper.instance.insertThought(thought);
    await loadThoughts();
  }

  Future<void> updateStatus(String id, String status) async {
    await DatabaseHelper.instance.updateThoughtStatus(id, status);
    await loadThoughts();
  }

  Future<void> updateContent(String id, String content) async {
    await DatabaseHelper.instance.updateThoughtContent(id, content);
    await loadThoughts();
  }

  Future<void> deleteThought(String id) async {
    await DatabaseHelper.instance.deleteThought(id);
    await loadThoughts();
  }
}
