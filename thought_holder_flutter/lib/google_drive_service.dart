import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'database_helper.dart';

// Extension to get authenticated HTTP client for Google APIs
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

class GoogleDriveService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope],
  );

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;

  Future<bool> get isSignedIn async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return false;
    }
    try {
      return await _googleSignIn.isSignedIn();
    } catch (_) {
      return false;
    }
  }
  GoogleSignInAccount? get currentUser => _currentUser;

  Future<bool> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      if (_currentUser != null) {
        final authHeaders = await _currentUser!.authHeaders;
        final authenticateClient = GoogleAuthClient(authHeaders);
        _driveApi = drive.DriveApi(authenticateClient);
        return true;
      }
    } catch (e) {
      print("Google Sign In Error: $e");
      rethrow;
    }
    return false;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentUser = null;
    _driveApi = null;
  }

  Future<void> syncThoughtsToDrive() async {
    if (_driveApi == null) {
      print("Drive API not initialized. Please sign in first.");
      return;
    }

    try {
      // 1. Get all local thoughts
      final db = await DatabaseHelper.instance.database;
      final localThoughts = await db.query('thoughts');

      // 2. Check if backup exists in AppDataFolder
      final fileList = await _driveApi!.files.list(
        spaces: 'appDataFolder',
        q: "name = 'thought_holder_backup.json'",
      );

      drive.File? backupFile;
      Map<String, dynamic> remoteData = {'thoughts': []};

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        backupFile = fileList.files!.first;
        // Download existing
        final media = await _driveApi!.files.get(
          backupFile.id!,
          downloadOptions: drive.DownloadOptions.fullMedia,
        ) as drive.Media;

        final stream = await media.stream.transform(utf8.decoder).join();
        remoteData = json.decode(stream);
      }

      // 3. Intelligent Merge (Simplified: Combine and dedup by id, preferring newest)
      final mergedMap = <String, Map<String, dynamic>>{};
      
      // Add remote
      for (var t in (remoteData['thoughts'] as List)) {
        mergedMap[t['id']] = Map<String, dynamic>.from(t);
      }
      
      // Helper to safely get the highest timestamp from a thought map
      int getLatestTimestamp(Map<String, dynamic>? thought) {
        if (thought == null) return 0;
        
        int parseTime(dynamic val) {
          if (val == null) return 0;
          if (val is int) return val;
          if (val is String) return int.tryParse(val) ?? 0;
          return 0;
        }

        final updated = parseTime(thought['updated_at']);
        final viewed = parseTime(thought['last_viewed_at']);
        final created = parseTime(thought['created_at']);
        
        int max = updated;
        if (viewed > max) max = viewed;
        if (created > max) max = created;
        
        return max;
      }

      // Add/Update local
      for (var t in localThoughts) {
        final existing = mergedMap[t['id']];
        if (existing == null || getLatestTimestamp(t) > getLatestTimestamp(existing)) {
          mergedMap[t['id'] as String] = Map<String, dynamic>.from(t);
        }
      }

      final mergedList = mergedMap.values.toList();
      final backupContent = json.encode({'thoughts': mergedList, 'timestamp': DateTime.now().millisecondsSinceEpoch});

      // 4. Upload merged back to Drive
      final uploadMedia = drive.Media(
        Stream.value(utf8.encode(backupContent)),
        backupContent.length,
      );

      if (backupFile != null) {
        // Update existing
        await _driveApi!.files.update(
          drive.File(),
          backupFile.id!,
          uploadMedia: uploadMedia,
        );
      } else {
        // Create new
        final newFile = drive.File()
          ..name = 'thought_holder_backup.json'
          ..parents = ['appDataFolder'];
        await _driveApi!.files.create(
          newFile,
          uploadMedia: uploadMedia,
        );
      }

      // 5. Update local database with merged data
      for (var t in mergedList) {
        final existingLocal = localThoughts.where((l) => l['id'] == t['id']).toList();
        if (existingLocal.isEmpty) {
          await db.insert('thoughts', t);
        } else if (getLatestTimestamp(t) > getLatestTimestamp(existingLocal.first)) {
          await db.update('thoughts', t, where: 'id = ?', whereArgs: [t['id']]);
        }
      }

      print("Sync complete!");
    } catch (e) {
      print("Sync Error: $e");
    }
  }
}
