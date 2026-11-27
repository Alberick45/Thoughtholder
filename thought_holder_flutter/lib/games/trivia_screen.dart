import 'package:flutter/material.dart';
import '../services/economy_config.dart';
import '../services/gamification_service.dart';
import 'trivia_repository.dart';

class TriviaScreen extends StatefulWidget { const TriviaScreen({super.key}); @override State<TriviaScreen> createState() => _TriviaScreenState(); }
class _TriviaScreenState extends State<TriviaScreen> {
  int level = 1; int qIndex = 0; int lives = EconomyConfig.livesPerDay; int reviveCost = EconomyConfig.reviveBaseCost;
  List<TriviaQuestion> questions = []; bool loading = true; String? message; Set<int> hidden = {};

  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { setState(()=>loading=true); questions = await TriviaRepository.questionsForLevel(level); qIndex=0; hidden={}; lives=EconomyConfig.livesPerDay; reviveCost=EconomyConfig.reviveBaseCost; if(mounted) setState(()=>loading=false); }
  Future<void> _answer(int i) async {
    if (qIndex>=questions.length) return;
    final q = questions[qIndex];
    final correct = i == q.correctIndex;
    if (correct) {
      message = 'Correct!';
    } else {
      lives--;
      message = 'Wrong - life lost.';
    }
    qIndex++;
    if (lives <= 0) {
      if (mounted) setState(() { hidden = {}; });
      return;
    }
    if (qIndex >= questions.length) {
      await GamificationService.instance.awardTriviaLevel(level);
      if (!mounted) return;
      setState(() { message = 'Level $level complete! +${EconomyConfig.triviaLevelCoinReward} coins, +${EconomyConfig.triviaLevelXpReward} XP'; });
      level++;
      await _load();
      return;
    }
    if (mounted) setState(()=>hidden={});
  }

  Future<void> _revive() async {
    final ok = await GamificationService.instance.spendCoins(reviveCost, 'trivia_revive', refId: 'revive:$level:${DateTime.now().millisecondsSinceEpoch}');
    if (!ok) { setState(()=>message='Not enough coins'); return; }
    lives = 1;
    reviveCost = (reviveCost * EconomyConfig.reviveMultiplier).clamp(EconomyConfig.reviveBaseCost, EconomyConfig.reviveCostCap);
    setState(()=>message='Revived!');
  }

  @override Widget build(BuildContext context){
    if (loading) return const Scaffold(body: Center(child:CircularProgressIndicator()));
    final dead = lives <= 0;
    final q = questions.isEmpty ? null : questions[qIndex.clamp(0, questions.length-1)];
    return Scaffold(appBar: AppBar(title: Text('Trivia L$level')), body: SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: q==null ? const Center(child: Text('No questions available')) : ListView(children:[
      Text('Lives: $lives  •  Q ${(qIndex+1).clamp(1, questions.length)}/${questions.length}'),
      const SizedBox(height:12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(q.question, style: const TextStyle(fontSize: 18)))),
      const SizedBox(height:12),
      for (int i=0;i<q.options.length;i++) if(!hidden.contains(i)) Padding(padding: const EdgeInsets.only(bottom:8), child: ElevatedButton(onPressed: dead?null:()=>_answer(i), child: Text(q.options[i]))),
      if (dead) ElevatedButton(onPressed: _revive, child: Text('Revive ($reviveCost coins)')),
      if (message!=null) Padding(padding: const EdgeInsets.only(top:8), child: Text(message!)),
    ]))));
  }
}
