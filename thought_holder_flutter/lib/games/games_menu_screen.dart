import 'package:flutter/material.dart';
import 'sort_game_screen.dart';
import 'trivia_screen.dart';

class GamesMenuScreen extends StatelessWidget {
  const GamesMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Games')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(context, icon: Icons.swap_vert_circle_outlined, title: 'Sort Game', subtitle: 'Sort unsorted thoughts into buckets and earn coins.', onTap: ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>const SortGameScreen()))),
            const SizedBox(height: 12),
            _card(context, icon: Icons.quiz_outlined, title: 'Trivia', subtitle: 'Answer questions, keep streaks, revive with coins.', onTap: ()=>Navigator.push(context, MaterialPageRoute(builder: (_)=>const TriviaScreen()))),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children:[
            Icon(icon, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle),
            ])),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
