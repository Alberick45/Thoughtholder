import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class TitleGenerator {
  static final RegExp _leadingFillerRegex = RegExp(
    r'^(you\s+know|i\s+mean|eh|um|uh|okay|ok|so|well|like|yeah|hmm)\b[-—–,.\s]*',
    caseSensitive: false,
  );

  static final RegExp _trailingPunctuationRegex = RegExp(
    r'[-—–,.\s:;!?…]+$',
  );

  /// Generates a concise title from the idea's content following strict auto-name rules.
  static String generate(String rawContent) {
    String text = rawContent.trim();
    if (text.isEmpty) return 'Quick note';

    // Normalize multiple whitespace and newlines to a single space
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Remove leading filler words iteratively
    while (true) {
      final match = _leadingFillerRegex.firstMatch(text);
      if (match != null && match.end > 0) {
        text = text.substring(match.end).trim();
      } else {
        break;
      }
    }

    // Strip any leading punctuation left after filler removal
    text = text.replaceAll(RegExp(r'^[-—–,.\s:;!?…]+'), '').trim();

    if (text.isEmpty) {
      return 'Quick note';
    }

    String result;
    if (text.length <= 40) {
      // Short ideas (40 characters or fewer) use their own text
      result = text;
    } else {
      // Take first meaningful phrase up to 40 characters, cut at a word boundary
      String sub = text.substring(0, 40);
      if (text.length > 40 && text[40] != ' ' && sub.contains(' ')) {
        final lastSpace = sub.lastIndexOf(' ');
        if (lastSpace > 0) {
          sub = sub.substring(0, lastSpace);
        }
      }
      result = sub;
    }

    // Remove trailing punctuation
    result = result.replaceAll(_trailingPunctuationRegex, '').trim();

    if (result.isEmpty || result.toLowerCase() == 'untitled') {
      return 'Quick note';
    }

    // Sentence case (capitalize first letter)
    result = _toSentenceCase(result);

    return result.isNotEmpty ? result : 'Quick note';
  }

  static String getIdeaName(Map<String, dynamic> thought) {
    final title = (thought['title'] as String?)?.trim();
    if (title != null && title.isNotEmpty && title.toLowerCase() != 'untitled') {
      return title;
    }
    final content = (thought['content'] as String?) ?? '';
    return generate(content);
  }

  static String _toSentenceCase(String input) {
    if (input.isEmpty) return input;
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      if (RegExp(r'[a-zA-Z]').hasMatch(char)) {
        return input.substring(0, i) + char.toUpperCase() + input.substring(i + 1);
      }
    }
    return input;
  }

  /// Suggests a better name via Groq API.
  /// Only called when explicitly tapped by user.
  static Future<String?> suggestGroqName({
    required String content,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty || content.trim().isEmpty) return null;

    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      },
      body: json.encode({
        'model': 'llama-3.1-8b-instant',
        'messages': [
          {
            'role': 'system',
            'content':
                'Summarize the idea into a title of up to 40 characters in sentence case. Return ONLY the title text without quotes, punctuation at the end, or preamble.',
          },
          {
            'role': 'user',
            'content': content,
          }
        ],
        'temperature': 0.3,
        'max_tokens': 20,
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final rawName = data['choices']?[0]?['message']?['content']?.toString().trim();
      if (rawName != null && rawName.isNotEmpty) {
        String cleaned = rawName
            .replaceAll(RegExp(r'^["' "'" r']+|["' "'" r']+$'), '')
            .replaceAll(_trailingPunctuationRegex, '')
            .trim();
        if (cleaned.length > 40) {
          final lastSpace = cleaned.substring(0, 40).lastIndexOf(' ');
          cleaned = lastSpace > 0 ? cleaned.substring(0, lastSpace) : cleaned.substring(0, 40);
        }
        cleaned = _toSentenceCase(cleaned);
        if (cleaned.isNotEmpty && cleaned.toLowerCase() != 'untitled') {
          return cleaned;
        }
      }
    }
    return null;
  }
}

class IdeaFormatters {
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  /// Short, readable time under name:
  /// "Today, 9:45 PM", "Yesterday, 4:10 PM", or "28 Oct, 7:18 PM"
  /// Year is shown only if it is not the current year.
  /// created_at = 0 or null shows "Date unknown" and no time.
  static String formatReadableTimestamp(int? createdAt) {
    if (createdAt == null || createdAt == 0) {
      return 'Date unknown';
    }

    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt).toLocal();
    final now = DateTime.now();

    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final isPm = hour >= 12;
    final h12 = (hour % 12 == 0) ? 12 : (hour % 12);
    final timeStr = '$h12:$minute ${isPm ? 'PM' : 'AM'}';

    final today = DateTime(now.year, now.month, now.day);
    final ideaDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(ideaDay).inDays;

    if (diffDays == 0) {
      return 'Today, $timeStr';
    } else if (diffDays == 1) {
      return 'Yesterday, $timeStr';
    } else {
      final monthStr = _months[dt.month - 1];
      if (dt.year == now.year) {
        return '${dt.day} $monthStr, $timeStr';
      } else {
        return '${dt.day} $monthStr ${dt.year}, $timeStr';
      }
    }
  }

  /// Small icon showing how idea was captured (voice or typed)
  static IconData? getCaptureIcon(dynamic source) {
    if (source == null) return null;
    final t = source.toString().toLowerCase().trim();
    if (t.isEmpty) return null;
    if (t.contains('voice') ||
        t.contains('audio') ||
        t.endsWith('.wav') ||
        t.endsWith('.m4a') ||
        t.endsWith('.mp3')) {
      return Icons.mic;
    } else if (t.contains('task') ||
        t.contains('type') ||
        t.contains('text') ||
        t.contains('note') ||
        t.contains('thought') ||
        t.contains('buy') ||
        t.contains('profile')) {
      return Icons.edit_note;
    }
    return null;
  }
}
