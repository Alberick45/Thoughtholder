import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math' as math;
import 'thought_provider.dart';
import 'utils/nlp_engine.dart';
import 'utils/title_generator.dart';
import 'widgets/keyboard_safe_sheet.dart';

class IdeaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> thought;

  const IdeaDetailScreen({super.key, required this.thought});

  @override
  State<IdeaDetailScreen> createState() => _IdeaDetailScreenState();
}

class _IdeaDetailScreenState extends State<IdeaDetailScreen> {
  late List<String> keywords;
  late List<Map<String, dynamic>> similarThoughts;

  @override
  void initState() {
    super.initState();
    final content = widget.thought['content'] ?? '';
    keywords = NLPEngine.extractKeywords(content, limit: 6);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = Provider.of<ThoughtProvider>(context, listen: false);
    similarThoughts = NLPEngine.findSimilarThoughts(widget.thought, provider.thoughts);
  }

  Future<void> _launchSearch(String query) async {
    final Uri url = Uri.parse('https://www.google.com/search?q=${Uri.encodeComponent(query)}');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not launch search for $query')));
      }
    }
  }

  void _showEditDialog(
    BuildContext context,
    ThoughtProvider provider,
    Map<String, dynamic> thought,
  ) {
    final thoughtId = thought['thought_id'] as String? ?? 'LOG';
    final controller = TextEditingController(text: thought['content'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => KeyboardSafeSheet(
        isDialog: true,
        maxWidth: 480,
        backgroundColor: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
        header: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('Edit $thoughtId',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ),
        pinnedFooter: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  final newContent = controller.text.trim();
                  if (newContent.isNotEmpty) {
                    Navigator.pop(ctx);
                    final now = DateTime.now().millisecondsSinceEpoch;
                    await provider.updateContent(thought['id'], newContent,
                        editedAt: now);
                    setState(() {
                      keywords =
                          NLPEngine.extractKeywords(newContent, limit: 6);
                    });
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 8,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Edit your idea...',
            hintStyle: TextStyle(color: Colors.white38),
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ThoughtProvider>(context);
    final currentThought = provider.thoughts.firstWhere(
      (t) => t['id'] == widget.thought['id'],
      orElse: () => widget.thought,
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          TitleGenerator.getIdeaName(currentThought),
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white70),
            onPressed: () => _showEditDialog(context, provider, currentThought),
            tooltip: 'Edit idea',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroHeader(context, currentThought),
              const SizedBox(height: 30),
              if (similarThoughts.isNotEmpty) ...[
                _buildSectionTitle('NEURAL GRAPH'),
                _buildMiniGraph(context),
                const SizedBox(height: 30),
              ],
              if (keywords.isNotEmpty) ...[
                _buildSectionTitle('EXTRACTED KEYWORDS'),
                _buildKeywordsSection(),
                const SizedBox(height: 30),
                _buildSectionTitle('WEB ENRICHMENT'),
                _buildWebResultsSection(),
                const SizedBox(height: 30),
              ],
              if (similarThoughts.isNotEmpty) ...[
                _buildSectionTitle('SIMILAR IDEAS'),
                _buildSimilarIdeasSection(),
                const SizedBox(height: 40),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Widget _buildHeroHeader(BuildContext context, Map<String, dynamic> thought) {
    final editedVal =
        thought['edited_at'] ?? thought['editedAt'];
    DateTime? editedDate;
    if (editedVal is int) {
      editedDate = DateTime.fromMillisecondsSinceEpoch(editedVal);
    } else if (editedVal is String) {
      editedDate = DateTime.tryParse(editedVal);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: -5,
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            thought['content'] ?? '',
            style: const TextStyle(
              fontSize: 18,
              height: 1.6,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (editedDate != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.edit_outlined, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  'Edited ${_formatDate(editedDate)}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          letterSpacing: 2.0,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildKeywordsSection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: keywords.map((kw) {
        return ActionChip(
          label: Text('#$kw', style: const TextStyle(color: Colors.white)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          side: const BorderSide(color: Colors.white10),
          onPressed: () => _launchSearch(kw),
        );
      }).toList(),
    );
  }

  Widget _buildWebResultsSection() {
    return Column(
      children: keywords.take(2).map((kw) {
        return Card(
          color: Theme.of(context).colorScheme.surface,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white10),
          ),
          child: InkWell(
            onTap: () => _launchSearch(kw),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.travel_explore, color: Colors.blueAccent, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Search: "$kw"', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text('Tap to explore web results and articles related to this topic.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.open_in_new, color: Colors.white24, size: 16),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSimilarIdeasSection() {
    return Column(
      children: similarThoughts.map((item) {
        final t = item;
        final similarity = (t['similarity_score'] as double) * 100;
        return Card(
          color: Theme.of(context).colorScheme.surface,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Colors.white10),
          ),
          child: InkWell(
            onTap: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => IdeaDetailScreen(thought: t)),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        t['thought_id'],
                        style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${similarity.toStringAsFixed(0)}% Match', style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 10, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t['content'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMiniGraph(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: NeuralGraphPainter(
            context: context,
            centerNode: widget.thought,
            orbitNodes: similarThoughts,
          ),
        ),
      ),
    );
  }
}

class NeuralGraphPainter extends CustomPainter {
  final BuildContext context;
  final Map<String, dynamic> centerNode;
  final List<Map<String, dynamic>> orbitNodes;

  NeuralGraphPainter({required this.context, required this.centerNode, required this.orbitNodes});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final primaryColor = Theme.of(context).primaryColor;

    final linePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.2)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    // Draw lines and orbiting nodes
    final int nodeCount = orbitNodes.length;
    final double radius = math.min(size.width, size.height) * 0.35;

    for (int i = 0; i < nodeCount; i++) {
      final double angle = (i * 2 * math.pi) / nodeCount;
      final double similarity = orbitNodes[i]['similarity_score'] as double;
      // Distance inversely proportional to similarity (higher similarity -> closer)
      final double adjustedRadius = radius * (1.2 - similarity); 
      
      final double x = center.dx + adjustedRadius * math.cos(angle);
      final double y = center.dy + adjustedRadius * math.sin(angle);
      final Offset orbitCenter = Offset(x, y);

      // Draw connection line
      linePaint.color = primaryColor.withValues(alpha: 0.1 + (similarity * 0.5));
      linePaint.strokeWidth = 1.0 + (similarity * 2);
      canvas.drawLine(center, orbitCenter, linePaint);

      // Draw orbiting node
      nodePaint.color = Colors.white.withValues(alpha: 0.3 + (similarity * 0.7));
      canvas.drawCircle(orbitCenter, 4 + (similarity * 4), nodePaint);
    }

    // Draw center node (pulsing effect simulation)
    nodePaint.color = primaryColor.withValues(alpha: 0.2);
    canvas.drawCircle(center, 24, nodePaint);
    nodePaint.color = primaryColor.withValues(alpha: 0.4);
    canvas.drawCircle(center, 16, nodePaint);
    nodePaint.color = primaryColor;
    canvas.drawCircle(center, 8, nodePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
