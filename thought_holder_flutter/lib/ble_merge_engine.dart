import 'dart:math';
import 'sync_identity.dart';

/// Structured result of a 2-way database merge
class MergeResult {
  final List<Map<String, dynamic>> finalThoughts;
  final List<Map<String, dynamic>> finalBuckets;
  final List<Map<String, dynamic>> finalTombstones;
  final List<Map<String, dynamic>> finalAliases;
  final int addedCount;
  final int updatedCount;
  final int trashedCount;
  final List<String> mergedBucketNames;

  const MergeResult({
    required this.finalThoughts,
    required this.finalBuckets,
    required this.finalTombstones,
    required this.finalAliases,
    required this.addedCount,
    required this.updatedCount,
    required this.trashedCount,
    required this.mergedBucketNames,
  });

  List<Map<String, dynamic>> get mergedThoughts => finalThoughts;
  List<Map<String, dynamic>> get mergedBuckets => finalBuckets;
  List<Map<String, dynamic>> get mergedTombstones => finalTombstones;
  Map<String, String> get bucketAliases {
    final map = <String, String>{};
    for (final a in finalAliases) {
      if (a['alias_id'] != null && a['canonical_id'] != null) {
        map[a['alias_id'] as String] = a['canonical_id'] as String;
      }
    }
    return map;
  }
  int get bucketsMergedCount => mergedBucketNames.length;

  /// Formats summary in plain words (Section 8)
  String toPlainSummary() {
    final parts = <String>[];
    if (addedCount > 0) {
      parts.add('Added $addedCount ${addedCount == 1 ? 'idea' : 'ideas'}');
    }
    if (updatedCount > 0) {
      parts.add('Updated $updatedCount');
    }
    if (trashedCount > 0) {
      parts.add('Moved $trashedCount to Trash');
    }
    if (mergedBucketNames.isNotEmpty) {
      final bNames = mergedBucketNames.toSet().join(', ');
      parts.add('Merged ${mergedBucketNames.length} ${mergedBucketNames.length == 1 ? 'bucket' : 'buckets'} ($bNames)');
    }

    if (parts.isEmpty) {
      return 'Already up to date. Nothing changed.';
    }
    return '${parts.join('. ')}.';
  }
}

/// Pure engine executing UPDATE 7 merge rules
class BleMergeEngine {
  /// Convenience alias for merge
  static MergeResult mergeDatasets({
    required List<Map<String, dynamic>> localThoughts,
    required List<Map<String, dynamic>> remoteThoughts,
    required List<Map<String, dynamic>> localBuckets,
    required List<Map<String, dynamic>> remoteBuckets,
    required List<Map<String, dynamic>> localTombstones,
    required List<Map<String, dynamic>> remoteTombstones,
    List<Map<String, dynamic>> localAliases = const [],
    List<Map<String, dynamic>> remoteAliases = const [],
    required String currentDeviceId,
    int? lastSyncTime,
  }) {
    return merge(
      localThoughts: localThoughts,
      remoteThoughts: remoteThoughts,
      localBuckets: localBuckets,
      remoteBuckets: remoteBuckets,
      localTombstones: localTombstones,
      remoteTombstones: remoteTombstones,
      localAliases: localAliases,
      remoteAliases: remoteAliases,
      coordinatorDeviceId: currentDeviceId,
      lastSyncTime: lastSyncTime,
    );
  }

  static String formatSummary({
    int addedCount = 0,
    int updatedCount = 0,
    int trashedCount = 0,
    List<String> mergedBucketNames = const [],
  }) {
    final res = MergeResult(
      finalThoughts: const [],
      finalBuckets: const [],
      finalTombstones: const [],
      finalAliases: const [],
      addedCount: addedCount,
      updatedCount: updatedCount,
      trashedCount: trashedCount,
      mergedBucketNames: mergedBucketNames,
    );
    return res.toPlainSummary();
  }

  /// Merges local and remote datasets deterministically.
  /// [coordinatorDeviceId] breaks ties deterministically on both devices.
  static MergeResult merge({
    required List<Map<String, dynamic>> localThoughts,
    required List<Map<String, dynamic>> remoteThoughts,
    required List<Map<String, dynamic>> localBuckets,
    required List<Map<String, dynamic>> remoteBuckets,
    required List<Map<String, dynamic>> localTombstones,
    required List<Map<String, dynamic>> remoteTombstones,
    required List<Map<String, dynamic>> localAliases,
    required List<Map<String, dynamic>> remoteAliases,
    required String coordinatorDeviceId,
    int? lastSyncTime,
  }) {
    int added = 0;
    int updated = 0;
    int trashed = 0;
    final mergedBucketNames = <String>[];

    // ──────────────────────────────────────────────────────────────────────────
    // 1. Merge Tombstones (90-day retention)
    // ──────────────────────────────────────────────────────────────────────────
    final now = DateTime.now().millisecondsSinceEpoch;
    final ninetyDaysMs = 90 * 24 * 60 * 60 * 1000;
    final allTombstonesMap = <String, Map<String, dynamic>>{};

    void addTombstone(Map<String, dynamic> t) {
      final id = t['id'] as String;
      final delAt = (t['deleted_at'] as num?)?.toInt() ?? now;
      if (now - delAt > ninetyDaysMs) return; // Prune older than 90 days

      final existing = allTombstonesMap[id];
      if (existing == null) {
        allTombstonesMap[id] = Map<String, dynamic>.from(t);
      } else {
        if (Hlc.compare(t['updated_at']?.toString(), existing['updated_at']?.toString()) > 0) {
          allTombstonesMap[id] = Map<String, dynamic>.from(t);
        }
      }
    }

    for (final t in localTombstones) {
      addTombstone(t);
    }
    for (final t in remoteTombstones) {
      addTombstone(t);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // 2. Merge Bucket Aliases
    // ──────────────────────────────────────────────────────────────────────────
    final aliasMap = <String, String>{}; // aliasId -> canonicalId
    for (final a in [...localAliases, ...remoteAliases]) {
      final aliasId = a['alias_id'] as String?;
      final canId = a['canonical_id'] as String?;
      if (aliasId != null && canId != null) {
        aliasMap[aliasId] = canId;
      }
    }

    // Resolve chained aliases
    String resolveAlias(String id) {
      var current = id;
      int depth = 0;
      while (aliasMap.containsKey(current) && depth < 10) {
        current = aliasMap[current]!;
        depth++;
      }
      return current;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // 3. Merge Buckets (Section 4)
    // ──────────────────────────────────────────────────────────────────────────
    final bucketMapById = <String, Map<String, dynamic>>{};
    final allRawBuckets = [...localBuckets, ...remoteBuckets];

    for (final b in allRawBuckets) {
      final id = resolveAlias(b['id'] as String? ?? b['name'] as String);
      if (allTombstonesMap.containsKey(id)) {
        // Bucket was deleted
        continue;
      }

      final existing = bucketMapById[id];
      if (existing == null) {
        bucketMapById[id] = Map<String, dynamic>.from(b)..['id'] = id;
      } else {
        // Newer HLC wins for name and icon
        final cmp = Hlc.compare(b['updated_at']?.toString(), existing['updated_at']?.toString());
        if (cmp > 0 || (cmp == 0 && (b['updated_by']?.toString() ?? '').compareTo(existing['updated_by']?.toString() ?? '') >= 0)) {
          bucketMapById[id] = Map<String, dynamic>.from(b)..['id'] = id;
        }
      }
    }

    // Two buckets created separately with the same name (ignoring case and whitespace) -> merge into ONE
    final normalizedNameToBucket = <String, Map<String, dynamic>>{};
    final newAliases = <Map<String, dynamic>>[];

    for (final b in bucketMapById.values.toList()) {
      final normName = (b['name'] as String).trim().toLowerCase();
      final existing = normalizedNameToBucket[normName];

      if (existing == null) {
        normalizedNameToBucket[normName] = b;
      } else {
        // Merge into one: keep the oldest createdAt as the real one
        final int cA = (existing['created_at'] as num?)?.toInt() ?? 0;
        final int cB = (b['created_at'] as num?)?.toInt() ?? 0;
        final Map<String, dynamic> canonical;
        final Map<String, dynamic> secondary;

        if (cA <= cB) {
          canonical = existing;
          secondary = b;
        } else {
          canonical = b;
          secondary = existing;
          normalizedNameToBucket[normName] = canonical;
        }

        final canId = canonical['id'] as String;
        final secId = secondary['id'] as String;

        aliasMap[secId] = canId;
        newAliases.add({
          'alias_id': secId,
          'canonical_id': canId,
          'created_at': now,
        });

        bucketMapById.remove(secId);
        mergedBucketNames.add(canonical['name'] as String);
      }
    }

    final finalBuckets = bucketMapById.values.toList();
    final validBucketIds = bucketMapById.keys.toSet();

    // ──────────────────────────────────────────────────────────────────────────
    // 4. Merge Thoughts (Section 4)
    // ──────────────────────────────────────────────────────────────────────────
    final thoughtMap = <String, Map<String, dynamic>>{};
    final conflictCopies = <Map<String, dynamic>>[];
    final localMap = {for (final t in localThoughts) t['id'] as String: t};
    final remoteMap = {for (final t in remoteThoughts) t['id'] as String: t};

    final allThoughtIds = {...localMap.keys, ...remoteMap.keys};

    // Pre-check: Deduplicate pre-update one-way copies (Section 4)
    // Treat two ideas as same if text is identical and createdAt is within 2 minutes (120,000ms)
    final deduplicatedPairs = <String, String>{}; // duplicateId -> canonicalId
    final localList = localThoughts.toList();
    for (int i = 0; i < localList.length; i++) {
      for (final r in remoteThoughts) {
        final tA = localList[i];
        final tB = r;
        if (tA['id'] != tB['id'] &&
            tA['content'] == tB['content'] &&
            tA['content'].toString().trim().isNotEmpty) {
          final int cA = (tA['created_at'] as num?)?.toInt() ?? 0;
          final int cB = (tB['created_at'] as num?)?.toInt() ?? 0;
          if ((cA - cB).abs() <= 120000) {
            // Keep the one with older createdAt or stable tie-break
            final can = cA <= cB ? tA['id'] as String : tB['id'] as String;
            final dup = cA <= cB ? tB['id'] as String : tA['id'] as String;
            deduplicatedPairs[dup] = can;
          }
        }
      }
    }

    for (final id in allThoughtIds) {
      if (deduplicatedPairs.containsKey(id)) {
        // Skip duplicate absorbed by canonical
        continue;
      }

      // Check if deleted
      if (allTombstonesMap.containsKey(id)) {
        final tomb = allTombstonesMap[id]!;
        final local = localMap[id];
        final remote = remoteMap[id];
        final latestLocal = local != null ? local['updated_at']?.toString() : null;
        final latestRemote = remote != null ? remote['updated_at']?.toString() : null;
        final latestThoughtHlc = [latestLocal, latestRemote]
            .whereType<String>()
            .fold<String>('', (prev, e) => Hlc.compare(e, prev) > 0 ? e : prev);

        if (Hlc.compare(tomb['updated_at']?.toString(), latestThoughtHlc) >= 0) {
          // Deletion wins!
          continue;
        }
      }

      final inLocal = localMap.containsKey(id);
      final inRemote = remoteMap.containsKey(id);

      if (inLocal && !inRemote) {
        thoughtMap[id] = Map<String, dynamic>.from(localMap[id]!);
        added++;
      } else if (!inLocal && inRemote) {
        thoughtMap[id] = Map<String, dynamic>.from(remoteMap[id]!);
        added++;
      } else {
        // Exists on BOTH devices -> Field-level winning merge
        final a = localMap[id]!;
        final b = remoteMap[id]!;

        final merged = Map<String, dynamic>.from(a);
        bool hasChanges = false;

        // Content (text) & conflict copy detection
        final hlcA = a['updated_at']?.toString();
        final hlcB = b['updated_at']?.toString();
        final contentA = (a['content'] as String?) ?? '';
        final contentB = (b['content'] as String?) ?? '';

        if (contentA != contentB) {
          final cmp = Hlc.compare(hlcA, hlcB);
          final bool aWins = cmp > 0 || (cmp == 0 && coordinatorDeviceId == a['updated_by']);

          final winningText = aWins ? contentA : contentB;
          final losingText = aWins ? contentB : contentA;

          merged['content'] = winningText;

          // If text was edited concurrently on both devices since last sync: save losing text as Conflict copy
          final int aEdit = (a['edited_at'] as num?)?.toInt() ?? 0;
          final int bEdit = (b['edited_at'] as num?)?.toInt() ?? 0;
          final int aRev = (a['revision'] as num?)?.toInt() ?? 1;
          final int bRev = (b['revision'] as num?)?.toInt() ?? 1;

          final bool concurrentEdit = (lastSyncTime != null)
              ? (aEdit > lastSyncTime && bEdit > lastSyncTime)
              : ((aEdit > 0 && bEdit > 0) || (aRev == bRev && a['updated_by'] != b['updated_by']));

          if (concurrentEdit && losingText.trim().isNotEmpty) {
            final conflictId = SyncIdentity.newUuid();
            conflictCopies.add({
              'id': conflictId,
              'thought_id': 'LOG-${now % 10000}',
              'content': 'Conflict copy: $losingText',
              'type': a['type'] ?? 'thought',
              'status': 'active',
              'tags': 'conflict-copy',
              'summary': '',
              'created_at': now,
              'last_viewed_at': now,
              'stale_score': 0,
              'linked_thoughts': '[]',
              'bucket': null,
              'bucket_id': null,
              'when_val': 'Soon',
              'time_val': 'Medium',
              'done': 0,
              'trashed': 0,
              'updated_at': Hlc.now(coordinatorDeviceId).toString(),
              'updated_by': coordinatorDeviceId,
              'revision': 1,
            });
          }
          hasChanges = true;
        }

        // Status: Trash and Done
        final cmpStatus = Hlc.compare(hlcA, hlcB);
        final bool statusAWins = cmpStatus > 0 || (cmpStatus == 0 && coordinatorDeviceId == a['updated_by']);
        final statusWinner = statusAWins ? a : b;

        merged['status'] = statusWinner['status'];
        merged['done'] = statusWinner['done'];
        merged['trashed'] = statusWinner['trashed'];
        merged['done_at'] = statusWinner['done_at'];
        merged['trashed_at'] = statusWinner['trashed_at'];

        if (merged['trashed'] == 1 && a['trashed'] != 1) {
          trashed++;
        }

        // When & Time
        final whenWinner = statusAWins ? a : b;
        merged['when_val'] = whenWinner['when_val'] ?? 'Soon';
        merged['time_val'] = whenWinner['time_val'] ?? 'Medium';

        // Title & Title Source (newer edit wins, without breaking older versions)
        final titleWinner = statusAWins ? a : b;
        final titleA = a['title'] as String?;
        final titleB = b['title'] as String?;
        final sourceA = a['title_source'] as String?;
        final sourceB = b['title_source'] as String?;

        if (titleWinner['title'] != null && (titleWinner['title'] as String).isNotEmpty) {
          merged['title'] = titleWinner['title'];
          merged['title_source'] = titleWinner['title_source'] ?? 'auto';
        } else {
          merged['title'] = titleA ?? titleB;
          merged['title_source'] = sourceA ?? sourceB ?? 'auto';
        }

        // Winner metadata
        merged['updated_at'] = Hlc.compare(hlcA, hlcB) >= 0 ? hlcA : hlcB;
        merged['updated_by'] = Hlc.compare(hlcA, hlcB) >= 0 ? a['updated_by'] : b['updated_by'];
        merged['revision'] = max((a['revision'] as num?)?.toInt() ?? 1, (b['revision'] as num?)?.toInt() ?? 1) + (hasChanges ? 1 : 0);

        thoughtMap[id] = merged;
        if (hasChanges) updated++;
      }
    }

    // Add conflict copies
    for (final cc in conflictCopies) {
      thoughtMap[cc['id'] as String] = cc;
      added++;
    }

    // Resolve bucket references for ALL thoughts (local-only, remote-only, merged)
    for (final entry in thoughtMap.entries) {
      final t = entry.value;
      var rawBucketId = t['bucket_id'] as String? ?? t['bucket'] as String?;
      if (rawBucketId != null) {
        rawBucketId = resolveAlias(rawBucketId);
      }
      if (rawBucketId != null && validBucketIds.contains(rawBucketId)) {
        t['bucket_id'] = rawBucketId;
        t['bucket'] = bucketMapById[rawBucketId]?['name'];
      } else {
        t['bucket_id'] = null;
        t['bucket'] = null;
      }
    }

    // ──────────────────────────────────────────────────────────────────────────
    // 5. Canonical LOG Number Resolution (Section 2)
    // ──────────────────────────────────────────────────────────────────────────
    // LOG numbers stay as display labels. If an incoming idea has the same LOG number as a different idea,
    // the newer idea (by createdAt) gets the next free number; decided once by coordinator.
    final usedLogNumbers = <int>{};
    int maxLogNum = 0;

    final thoughtsList = thoughtMap.values.toList();
    thoughtsList.sort((a, b) {
      final int cA = (a['created_at'] as num?)?.toInt() ?? 0;
      final int cB = (b['created_at'] as num?)?.toInt() ?? 0;
      return cA.compareTo(cB); // oldest first
    });

    for (final t in thoughtsList) {
      final logStr = (t['thought_id'] as String? ?? '').replaceFirst('LOG-', '');
      final logNum = int.tryParse(logStr);
      if (logNum != null) {
        if (!usedLogNumbers.contains(logNum)) {
          usedLogNumbers.add(logNum);
          maxLogNum = max(maxLogNum, logNum);
        } else {
          // Duplicate LOG number on a newer idea -> assign next free number
          maxLogNum++;
          t['thought_id'] = 'LOG-${maxLogNum.toString().padLeft(4, '0')}';
          usedLogNumbers.add(maxLogNum);
        }
      }
    }

    return MergeResult(
      finalThoughts: thoughtsList,
      finalBuckets: finalBuckets,
      finalTombstones: allTombstonesMap.values.toList(),
      finalAliases: [...localAliases, ...newAliases],
      addedCount: added,
      updatedCount: updated,
      trashedCount: trashed,
      mergedBucketNames: mergedBucketNames,
    );
  }

  /// Scans for exact-text duplicate ideas created within the database
  static List<List<Map<String, dynamic>>> findExactTextDuplicates(List<Map<String, dynamic>> thoughts) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final t in thoughts) {
      final text = (t['content'] as String? ?? '').trim();
      if (text.isEmpty) continue;
      groups.putIfAbsent(text, () => []).add(t);
    }
    return groups.values.where((list) => list.length > 1).toList();
  }
}
