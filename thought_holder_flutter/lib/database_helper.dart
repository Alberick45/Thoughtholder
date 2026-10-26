import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('thoughts.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE thoughts (
  id TEXT PRIMARY KEY,
  thought_id TEXT NOT NULL,
  content TEXT NOT NULL,
  type TEXT NOT NULL,
  status TEXT NOT NULL,
  tags TEXT,
  summary TEXT,
  created_at INTEGER NOT NULL,
  last_viewed_at INTEGER NOT NULL,
  stale_score INTEGER NOT NULL,
  linked_thoughts TEXT
)
''');
  }

  Future<void> insertThought(Map<String, dynamic> thought) async {
    final db = await instance.database;
    await db.insert('thoughts', thought, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> fetchAllThoughts() async {
    final db = await instance.database;
    return await db.query('thoughts', orderBy: 'created_at DESC');
  }

  Future<void> updateThoughtStatus(String id, String status) async {
    final db = await instance.database;
    await db.update(
      'thoughts',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateThoughtContent(String id, String content) async {
    final db = await instance.database;
    await db.update(
      'thoughts',
      {'content': content},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteThought(String id) async {
    final db = await instance.database;
    await db.delete('thoughts', where: 'id = ?', whereArgs: [id]);
  }
}
