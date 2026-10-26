import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'thought_provider.dart';
import 'idea_detail_screen.dart';

class StreamScreen extends StatefulWidget {
  const StreamScreen({Key? key}) : super(key: key);

  @override
  _StreamScreenState createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  String _currentFilter = 'active'; // active, completed, trash

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Filter Chips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildFilterChip('ACTIVE', 'active'),
              const SizedBox(width: 8),
              _buildFilterChip('DONE', 'completed'),
              const SizedBox(width: 8),
              _buildFilterChip('TRASH', 'vaulted_trash'),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Consumer<ThoughtProvider>(
              builder: (context, provider, child) {
                final thoughts = provider.thoughts.where((t) {
                  final status = t['status'];
                  if (_currentFilter == 'active') {
                    return status != 'vaulted_trash' && status != 'completed';
                  } else if (_currentFilter == 'completed') {
                    return status == 'completed';
                  } else {
                    return status == 'vaulted_trash';
                  }
                }).toList();
                
                if (thoughts.isEmpty) {
                  return const Center(
                    child: Text(
                      'No thoughts captured yet.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: thoughts.length,
                  itemBuilder: (context, index) {
                    final thought = thoughts[index];
                    return Dismissible(
                      key: Key(thought['id']),
                      direction: DismissDirection.horizontal,
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 20),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.check, color: Colors.white),
                      ),
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) {
                        if (direction == DismissDirection.endToStart) {
                          provider.updateStatus(thought['id'], 'vaulted_trash');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Eradicated ${thought['thought_id']}")),
                          );
                        } else if (direction == DismissDirection.startToEnd) {
                          provider.updateStatus(thought['id'], 'completed');
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Marked ${thought['thought_id']} as done!")),
                          );
                        }
                      },
                      child: ThoughtCardWidget(thought: thought, provider: provider),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterValue) {
    final bool isActive = _currentFilter == filterValue;
    return GestureDetector(
      onTap: () => setState(() => _currentFilter = filterValue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Theme.of(context).colorScheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isActive ? Theme.of(context).primaryColor.withOpacity(0.5) : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Theme.of(context).primaryColor : Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class ThoughtCardWidget extends StatelessWidget {
  final Map<String, dynamic> thought;
  final ThoughtProvider provider;

  const ThoughtCardWidget({Key? key, required this.thought, required this.provider}) : super(key: key);

  IconData _getIconForType(String type) {
    switch (type) {
      case 'task': return Icons.check_circle_outline;
      case 'buy': return Icons.shopping_cart_outlined;
      case 'idea': return Icons.lightbulb_outline;
      case 'event': return Icons.event;
      case 'suggestion': return Icons.bolt;
      case 'note': return Icons.notes;
      case 'thought':
      default:
        return Icons.chat_bubble_outline;
    }
  }

  Color _getColorForType(String type, BuildContext context) {
    switch (type) {
      case 'task': return Colors.blueAccent;
      case 'buy': return Colors.greenAccent;
      case 'idea': return Colors.amberAccent;
      case 'event': return Colors.purpleAccent;
      case 'suggestion': return Theme.of(context).primaryColor;
      default: return Colors.white54;
    }
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => IdeaDetailScreen(thought: thought),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutQuart;

          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final TextEditingController _controller = TextEditingController(text: thought['content']);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('Edit ${thought['thought_id']}', style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 14)),
        content: TextField(
          controller: _controller,
          maxLines: null,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              provider.updateContent(thought['id'], _controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('SAVE', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  void _toggleCheckbox(String line, int lineIndex, bool isCurrentlyChecked) {
    final String content = thought['content'] ?? '';
    final List<String> lines = content.split('\n');
    
    String updatedLine = line;
    if (isCurrentlyChecked) {
      // Uncheck: Replace '✓ ' with '1. ' (or '-' or whatever, defaulting to '1. ' for simplicity)
      updatedLine = line.replaceFirst(RegExp(r'^✓\s*'), '1. ');
    } else {
      // Check: Replace '1. ' or '- [ ]' with '✓ '
      updatedLine = line.replaceFirst(RegExp(r'^(\d+\.|-\s*\[\s*\])\s*'), '✓ ');
    }

    lines[lineIndex] = updatedLine;
    provider.updateContent(thought['id'], lines.join('\n'));
  }

  Widget _buildContent(BuildContext context) {
    final String content = thought['content'] ?? '';
    final List<String> lines = content.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.asMap().entries.map((entry) {
        final int index = entry.key;
        final String line = entry.value;

        final bool isChecked = line.trimLeft().startsWith('✓ ');
        final bool isUnchecked = RegExp(r'^(\d+\.|-\s*\[\s*\])\s+').hasMatch(line.trimLeft());

        if (isChecked || isUnchecked) {
          // Interactive Checkbox line
          final displayText = line.replaceFirst(RegExp(r'^(✓|\d+\.|-\s*\[\s*\])\s+'), '').trim();
          return InkWell(
            onTap: () => _toggleCheckbox(line, index, isChecked),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isChecked ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 20,
                    color: isChecked ? Colors.green : Colors.white54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayText,
                      style: TextStyle(
                        color: isChecked ? Colors.white38 : Colors.white,
                        fontSize: 16,
                        decoration: isChecked ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Standard text line
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2.0),
          child: Text(
            line,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              height: 1.4,
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String type = thought['type'] ?? 'thought';
    final typeIcon = _getIconForType(type);
    final typeColor = _getColorForType(type, context);
    final bool isDesktop = !(thought['thought_id'] as String).startsWith('LOG-');

    return GestureDetector(
      onTap: () => _navigateToDetail(context),
      child: Card(
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white10),
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(typeIcon, size: 16, color: typeColor),
                      const SizedBox(width: 8),
                      Text(
                        thought['thought_id'],
                        style: TextStyle(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (isDesktop) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.computer, size: 12, color: Colors.white38),
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      // Mark as Done — always visible (needed on desktop where swipe doesn't work)
                      if (thought['status'] != 'completed' && thought['status'] != 'vaulted_trash')
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline, size: 18, color: Colors.green),
                          tooltip: 'Mark as done',
                          onPressed: () {
                            provider.updateStatus(thought['id'], 'completed');
                          },
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      if (thought['status'] != 'completed' && thought['status'] != 'vaulted_trash')
                        const SizedBox(width: 12),
                      // Trash button for active thoughts
                      if (thought['status'] != 'completed' && thought['status'] != 'vaulted_trash')
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white30),
                          tooltip: 'Move to trash',
                          onPressed: () {
                            provider.updateStatus(thought['id'], 'vaulted_trash');
                          },
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      if (thought['status'] != 'completed' && thought['status'] != 'vaulted_trash')
                        const SizedBox(width: 12),
                      // Restore button for done/trash
                      if (thought['status'] == 'completed' || thought['status'] == 'vaulted_trash')
                        IconButton(
                          icon: const Icon(Icons.restore, size: 16, color: Colors.white54),
                          tooltip: 'Restore',
                          onPressed: () {
                            provider.updateStatus(thought['id'], 'active');
                          },
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      if (thought['status'] == 'completed' || thought['status'] == 'vaulted_trash')
                        const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 16, color: Colors.white54),
                        onPressed: () => _showEditDialog(context),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildContent(context),
            ],
          ),
        ),
      ),
    );
  }
}
