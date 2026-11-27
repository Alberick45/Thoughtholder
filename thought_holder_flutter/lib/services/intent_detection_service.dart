class IntentResult {
  final String intentType;
  final double confidence;
  final String? action;
  final String? measure;
  final DateTime? deadline;
  final String? trigger;
  final int? goalTarget;
  final String? goalUnit;

  const IntentResult({
    required this.intentType,
    required this.confidence,
    this.action,
    this.measure,
    this.deadline,
    this.trigger,
    this.goalTarget,
    this.goalUnit,
  });
}

class IntentDetectionService {
  static IntentResult detect(String raw, {DateTime? now}) {
    final text = raw.trim();
    final lower = text.toLowerCase();
    final n = now ?? DateTime.now();
    var intent = 'idea';
    var conf = 0.35;
    if (RegExp(r'\b(remind me|remember to|tomorrow|next week|at \d)').hasMatch(lower)) {
      intent = 'reminder'; conf = 0.8;
    } else if (RegExp(r'\b(every day|daily|weekly|every morning|every night|habit)\b').hasMatch(lower)) {
      intent = 'habit'; conf = 0.78;
    } else if (RegExp(r'\b(learn|become|improve|get better|master|study|goal)\b').hasMatch(lower)) {
      intent = 'goal'; conf = 0.72;
    } else if (RegExp(r'\b(buy|call|email|send|finish|submit|pay|book|clean|fix|write|make|do)\b').hasMatch(lower)) {
      intent = 'task'; conf = 0.7;
    }

    DateTime? deadline;
    if (lower.contains('tomorrow')) {
      final d = n.add(const Duration(days: 1));
      deadline = DateTime(d.year, d.month, d.day, 9);
    } else if (lower.contains('today')) {
      deadline = DateTime(n.year, n.month, n.day, 18);
    }

    String? measure;
    final m = RegExp(r'(\d+\s*(minutes?|mins?|hours?|pages?|times?))').firstMatch(lower);
    if (m != null) measure = m.group(1);
    measure ??= intent == 'task' ? 'Done once' : intent == 'habit' ? 'Do it today' : intent == 'goal' ? 'Make progress today' : null;

    String? trigger;
    if (intent == 'habit') trigger = lower.contains('morning') ? 'In the morning' : lower.contains('night') ? 'At night' : 'After an existing routine';
    if (intent == 'goal') trigger = 'At a set daily time';

    int? goalTarget;
    String? goalUnit;
    final gm = RegExp(r'(\d+)\s*(minutes?|mins?|hours?|pages?|times?)').firstMatch(lower);
    if (gm != null) {
      final v = int.tryParse(gm.group(1)!);
      final u = gm.group(2)!;
      if (v != null) {
        goalTarget = u.startsWith('hour') ? v * 60 : v;
        goalUnit = u.contains('page') ? 'pages' : u.contains('time') ? 'times' : 'minutes';
      }
    }

    final action = text.isEmpty ? null : (text.length > 80 ? text.substring(0, 80).trim() : text);
    return IntentResult(intentType: intent, confidence: conf, action: action, measure: measure, deadline: deadline, trigger: trigger, goalTarget: goalTarget, goalUnit: goalUnit);
  }

  static List<String> defaultSubSteps(String intent, String? action) {
    final a = (action ?? 'Do it').trim();
    final shortA = a.length > 40 ? '${a.substring(0, 40)}...' : a;
    if (intent == 'habit') return ['Prepare', shortA, 'Mark done'];
    if (intent == 'goal') return ['Define first step', 'Do 10 minutes', 'Record progress'];
    return ['Open what you need', shortA, 'Mark done'];
  }
}
