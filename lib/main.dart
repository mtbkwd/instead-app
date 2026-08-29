import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(const PokerTrainerApp());

class PokerTrainerApp extends StatelessWidget {
  const PokerTrainerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Poker Trainer',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0E1417),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF23C483),
          brightness: Brightness.dark,
        ),
      ),
      home: const TrainerScreen(),
    );
  }
}

class TrainerScreen extends StatefulWidget {
  const TrainerScreen({super.key});

  @override
  State<TrainerScreen> createState() => _TrainerScreenState();
}

class _TrainerScreenState extends State<TrainerScreen> {
  final Random rng = Random();

  final List<String> positions = ['UTG', 'HJ', 'CO', 'BTN', 'SB', 'BB'];
  final List<String> ranks = ['2','3','4','5','6','7','8','9','T','J','Q','K','A'];
  final List<String> suits = ['♠','♥','♦','♣'];

  late List<String> deck;
  String heroPosition = 'BTN';
  List<String> hero = [];
  List<String> board = [];
  String street = 'PRE-FLOP';
  String villainAction = '';
  String feedback = 'Choose the best action.';
  int score = 0;
  int decisions = 0;
  int pot = 2;
  bool handOver = false;

  @override
  void initState() {
    super.initState();
    _newHand();
  }

  void _makeDeck() {
    deck = [
      for (final r in ranks)
        for (final s in suits) '$r$s'
    ]..shuffle(rng);
  }

  void _newHand() {
    _makeDeck();
    heroPosition = positions[rng.nextInt(positions.length)];
    hero = [deck.removeLast(), deck.removeLast()];
    board = [];
    street = 'PRE-FLOP';
    pot = 2;
    villainAction = heroPosition == 'UTG'
        ? 'Action folds to you.'
        : ['Action folds to you.', 'One player opens to 2.5 BB.', 'One limper enters the pot.'][rng.nextInt(3)];
    feedback = 'Choose the best action.';
    handOver = false;
    setState(() {});
  }

  int _preflopStrength() {
    int value(String card) => ranks.indexOf(card[0]) + 2;
    final a = value(hero[0]);
    final b = value(hero[1]);
    var score = 0;
    if (a == b) score += 6 + max(0, a - 8);
    score += max(a, b) >= 14 ? 4 : max(a, b) >= 13 ? 3 : max(a, b) >= 12 ? 2 : 0;
    if (hero[0][1] == hero[1][1]) score += 2;
    if ((a - b).abs() <= 2) score += 1;
    return score;
  }

  String _bestAction() {
    final s = _preflopStrength();
    if (street == 'PRE-FLOP') {
      if (s >= 8) return 'Raise';
      if (s >= 5) return villainAction.contains('opens') ? 'Call' : 'Raise';
      return 'Fold';
    }
    final pair = _hasPair();
    if (pair && rng.nextDouble() < 0.65) return 'Raise';
    if (s >= 5) return 'Call';
    return rng.nextDouble() < 0.2 ? 'Raise' : 'Fold';
  }

  bool _hasPair() {
    final all = [...hero, ...board];
    final counts = <String, int>{};
    for (final c in all) {
      counts[c[0]] = (counts[c[0]] ?? 0) + 1;
    }
    return counts.values.any((v) => v >= 2);
  }

  void _choose(String action) {
    if (handOver) return;
    final best = _bestAction();
    decisions++;
    final correct = action == best;
    if (correct) score++;

    feedback = correct
        ? 'Good decision. $best is the preferred action in this simplified training model.'
        : 'Better line: $best. This spot is currently scored using a simplified range model.';

    if (action == 'Fold' || street == 'RIVER') {
      handOver = true;
      setState(() {});
      return;
    }

    _advanceStreet();
  }

  void _advanceStreet() {
    if (street == 'PRE-FLOP') {
      board.addAll([deck.removeLast(), deck.removeLast(), deck.removeLast()]);
      street = 'FLOP';
    } else if (street == 'FLOP') {
      board.add(deck.removeLast());
      street = 'TURN';
    } else if (street == 'TURN') {
      board.add(deck.removeLast());
      street = 'RIVER';
    }
    pot += 2 + rng.nextInt(5);
    villainAction = 'Opponent checks to you.';
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final accuracy = decisions == 0 ? 0 : (score * 100 / decisions).round();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('POKER TRAINER', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('$accuracy%', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Score $score  •  Decisions $decisions', style: TextStyle(color: Colors.white.withValues(alpha: .65))),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: const Color(0xFF172126),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('6-max  •  100 BB  •  $heroPosition', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('Pot $pot BB'),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Text(street, style: TextStyle(color: Colors.white.withValues(alpha: .55), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(
                      board.isEmpty ? '•  •  •' : board.join('   '),
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 30),
                    const Text('YOUR HAND', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(hero.join('   '), style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(villainAction, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Text(feedback, style: TextStyle(fontSize: 15, height: 1.4, color: Colors.white.withValues(alpha: .75))),
              const Spacer(),
              if (!handOver)
                Row(
                  children: [
                    Expanded(child: _ActionButton(label: 'FOLD', onTap: () => _choose('Fold'))),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionButton(label: 'CALL', onTap: () => _choose('Call'))),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionButton(label: 'RAISE', onTap: () => _choose('Raise'))),
                  ],
                )
              else
                FilledButton(
                  onPressed: _newHand,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
                  child: const Text('NEXT HAND'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
