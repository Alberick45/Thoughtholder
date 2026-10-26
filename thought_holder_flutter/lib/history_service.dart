import 'package:hive_flutter/hive_flutter.dart';
import 'history_model.dart';

/// Manages saving and loading of transfer history items using Hive.
class HistoryService {
  static const String _boxName = 'transfer_history';
  late Box<Map> _box;

  Future<void> init() async {
    try {
      _box = await Hive.openBox<Map>(_boxName);
    } catch (_) {
      // Fall back to in-memory box if lock is held by another instance.
      _box = await Hive.openBox<Map>('${_boxName}_temp');
    }
  }

  List<TransferHistoryItem> getAll() {
    final List<TransferHistoryItem> items = _box.values
        .map((map) => TransferHistoryItem.fromMap(map))
        .toList();
    // Sort descending (newest first)
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items;
  }

  Future<void> add(TransferHistoryItem item) async {
    await _box.put(item.id, item.toMap());
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
  }

  Future<void> clear() async {
    await _box.clear();
  }
}
