import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/economy_config.dart';

class TriviaQuestion {
  final String id; final int level; final String category; final String question; final List<String> options; final int correctIndex; final String? explanation; final String source; final String license;
  const TriviaQuestion({required this.id, required this.level, required this.category, required this.question, required this.options, required this.correctIndex, this.explanation, this.source = 'Unknown', this.license = 'Unknown'});
  factory TriviaQuestion.fromJson(Map<String, dynamic> j) => TriviaQuestion(
    id: j['id'].toString(), level: (j['level'] as num? ?? 1).toInt(), category: (j['category'] ?? 'General Knowledge').toString(), question: j['question'].toString(),
    options: (j['options'] as List).map((e)=>e.toString()).toList(), correctIndex: (j['correctIndex'] as num).toInt(), explanation: j['explanation']?.toString(),
    source: (j['source'] ?? 'Unknown').toString(), license: (j['license'] ?? 'Unknown').toString(),
  );
}

class TriviaPack { final String id; final String name; final int unlockCost; final List<TriviaQuestion> questions;
  const TriviaPack({required this.id, required this.name, required this.unlockCost, required this.questions});
}

class TriviaRepository {
  static List<TriviaPack>? _packs;
  static Future<List<TriviaPack>> loadPacks() async {
    if (_packs != null) return _packs!;
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final files = manifest.listAssets().where((a)=>a.startsWith('assets/trivia/') && a.endsWith('.json')).toList()
      ..sort();
    if (!files.contains('assets/trivia_questions.json')) files.insert(0, 'assets/trivia_questions.json');
    final packs = <TriviaPack>[];
    final seenIds = <String>{};
    final seenQuestions = <String>{};
    for (final file in files) {
      final raw = await rootBundle.loadString(file);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      for (final p in (data['packs'] as List? ?? [])) {
        final m = Map<String, dynamic>.from(p as Map);
        final qs = <TriviaQuestion>[];
        for (final q in (m['questions'] as List? ?? [])) {
          final tq = TriviaQuestion.fromJson(Map<String, dynamic>.from(q as Map));
          if (tq.question.trim().isEmpty || tq.options.length != 4) continue;
          if (tq.correctIndex < 0 || tq.correctIndex > 3) continue;
          final qKey = tq.question.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
          if (!seenIds.add(tq.id) || !seenQuestions.add(qKey)) continue;
          qs.add(tq);
        }
        if (qs.isNotEmpty) packs.add(TriviaPack(id: m['id'].toString(), name: m['name'].toString(), unlockCost: (m['unlockCost'] as num? ?? 0).toInt(), questions: qs));
      }
    }
    _packs = packs;
    return packs;
  }

  static Future<List<TriviaQuestion>> questionsForLevel(int level, {Set<String> ownedPacks = const {'starter'}}) async {
    final packs = await loadPacks();
    final owned = packs.where((p)=>ownedPacks.contains(p.id)).expand((p)=>p.questions).toList();
    final levelQs = owned.where((q)=>q.level==level).toList();
    final fallback = owned.isNotEmpty ? owned : packs.expand((p)=>p.questions).toList();
    final pool = levelQs.isNotEmpty ? levelQs : fallback;
    pool.shuffle();
    return pool.take(EconomyConfig.triviaQuestionsPerLevel).toList();
  }
}
