class NLPEngine {
  static const Set<String> _stopWords = {
    'i', 'me', 'my', 'myself', 'we', 'our', 'ours', 'ourselves', 'you', 'your', 'yours', 
    'yourself', 'yourselves', 'he', 'him', 'his', 'himself', 'she', 'her', 'hers', 
    'herself', 'it', 'its', 'itself', 'they', 'them', 'their', 'theirs', 'themselves', 
    'what', 'which', 'who', 'whom', 'this', 'that', 'these', 'those', 'am', 'is', 'are', 
    'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had', 'having', 'do', 'does', 
    'did', 'doing', 'a', 'an', 'the', 'and', 'but', 'if', 'or', 'because', 'as', 'until', 
    'while', 'of', 'at', 'by', 'for', 'with', 'about', 'against', 'between', 'into', 
    'through', 'during', 'before', 'after', 'above', 'below', 'to', 'from', 'up', 'down', 
    'in', 'out', 'on', 'off', 'over', 'under', 'again', 'further', 'then', 'once', 'here', 
    'there', 'when', 'where', 'why', 'how', 'all', 'any', 'both', 'each', 'few', 'more', 
    'most', 'other', 'some', 'such', 'no', 'nor', 'not', 'only', 'own', 'same', 'so', 
    'than', 'too', 'very', 's', 't', 'can', 'will', 'just', 'don', 'should', 'now',
    'im', 'ive', 'like', 'get', 'got', 'make', 'made', 'okay', 'ill', 'say', 'something', 'saying'
  };

  /// Extracts keywords by removing stop words and returning the most frequent or distinct words and phrases
  static List<String> extractKeywords(String text, {int limit = 5}) {
    if (text.isEmpty) return [];

    // Normalize text
    final cleanText = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final rawWords = cleanText.split(RegExp(r'\s+'));
    final words = rawWords.where((w) => w.length > 2 && !_stopWords.contains(w)).toList();

    final phraseCounts = <String, int>{};

    // Single words
    for (final word in words) {
      phraseCounts[word] = (phraseCounts[word] ?? 0) + 1;
    }

    // Bigrams (two-word phrases)
    for (int i = 0; i < words.length - 1; i++) {
      final bigram = '${words[i]} ${words[i + 1]}';
      phraseCounts[bigram] = (phraseCounts[bigram] ?? 0) + 2; // Weight phrases slightly higher
    }

    // Trigrams (three-word phrases)
    for (int i = 0; i < words.length - 2; i++) {
      final trigram = '${words[i]} ${words[i + 1]} ${words[i + 2]}';
      phraseCounts[trigram] = (phraseCounts[trigram] ?? 0) + 3;
    }

    // Sort by frequency/weight
    final sortedPhrases = phraseCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Return top N
    return sortedPhrases.take(limit).map((e) => e.key).toList();
  }

  /// Calculates a simple Jaccard similarity score between two texts based on keywords
  static double calculateSimilarity(String text1, String text2) {
    if (text1.isEmpty || text2.isEmpty) return 0.0;

    final keywords1 = extractKeywords(text1, limit: 20).toSet();
    final keywords2 = extractKeywords(text2, limit: 20).toSet();

    if (keywords1.isEmpty || keywords2.isEmpty) return 0.0;

    final intersection = keywords1.intersection(keywords2).length;
    final union = keywords1.union(keywords2).length;

    return intersection / union;
  }

  /// Finds similar thoughts from a list
  static List<Map<String, dynamic>> findSimilarThoughts(
      Map<String, dynamic> sourceThought, 
      List<Map<String, dynamic>> allThoughts, 
      {int limit = 3, double threshold = 0.05}) {
    
    final sourceContent = sourceThought['content'] as String? ?? '';
    final sourceId = sourceThought['id'];
    
    final List<Map<String, dynamic>> scoredThoughts = [];

    for (final t in allThoughts) {
      if (t['id'] == sourceId) continue;
      if (t['status'] == 'vaulted_trash') continue;

      final targetContent = t['content'] as String? ?? '';
      final score = calculateSimilarity(sourceContent, targetContent);

      if (score >= threshold) {
        scoredThoughts.add({
          'thought': t,
          'similarity': score,
        });
      }
    }

    scoredThoughts.sort((a, b) => (b['similarity'] as double).compareTo(a['similarity'] as double));

    return scoredThoughts.take(limit).map((e) {
      final t = Map<String, dynamic>.from(e['thought']);
      t['similarity_score'] = e['similarity'];
      return t;
    }).toList();
  }
}
