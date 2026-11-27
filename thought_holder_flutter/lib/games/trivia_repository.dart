import 'dart:convert';
import 'package:flutter/services.dart';
import '../services/economy_config.dart';

class TriviaQuestion {
  final String id; final int level; final String question; final List<String> options; final int correctIndex; final String? explanation;
  const TriviaQuestion({required this.id, required this.level, required this.question, required this.options, required this.correctIndex, this.explanation});
  factory TriviaQuestion.fromJson(Map<String, dynamic> j) => TriviaQuestion(
    id: j['id'].toString(), level: (j['level'] as num).toInt(), question: j['question'].toString(),
    options: (j['options'] as List).map((e)=>e.toString()).toList(), correctIndex: (j['correctIndex'] as num).toInt(), explanation: j['explanation']?.toString(),
  );
}

class TriviaPack { final String id; final String name; final int unlockCost; final List<TriviaQuestion> questions;
  const TriviaPack({required this.id, required this.name, required this.unlockCost, required this.questions});
}

class TriviaRepository {
  static List<TriviaPack>? _packs;
  static Future<List<TriviaPack>> loadPacks() async {
    if (_packs != null) return _packs!;
    final raw = await rootBundle.loadString('assets/trivia_questions.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final packs = <TriviaPack>[];
    final seenIds = <String>{};
    for (final p in (data['packs'] as List? ?? [])) {
      final m = Map<String, dynamic>.from(p as Map);
      final qs = <TriviaQuestion>[];
      for (final q in (m['questions'] as List? ?? [])) {
        final tq = TriviaQuestion.fromJson(Map<String, dynamic>.from(q as Map));
        if (tq.options.length != 4) continue;
        if (tq.correctIndex < 0 || tq.correctIndex > 3) continue;
        if (!seenIds.add(tq.id)) continue;
        qs.add(tq);
      }
      packs.add(TriviaPack(id: m['id'].toString(), name: m['name'].toString(), unlockCost: (m['unlockCost'] as num? ?? 0).toInt(), questions: qs));
    }
    _packs = packs;
    return packs;
  }

  static Future<List<TriviaQuestion>> questionsForLevel(int level, {Set<String> ownedPacks = const {'starter'}}) async {
    final packs = await loadPacks();
    final all = packs.where((p)=>ownedPacks.contains(p.id)).expand((p)=>p.questions).where((q)=>q.level==level).toList();
    if (all.isEmpty) return packs.expand((p)=>p.questions).take(EconomyConfig.triviaQuestionsPerLevel).toList();
    return all.take(EconomyConfig.triviaQuestionsPerLevel).toList();
  }
}
