import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const InsteadApp());

class InsteadApp extends StatelessWidget {
  const InsteadApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Instead',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF4F1EA),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A34)),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: const Color(0xFFF7F6F2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Color(0xFF1E3A34), width: 1.5),
            ),
          ),
        ),
        home: const FeedScreen(),
      );
}

enum CardKind { learn, think, create, remember, decide }

enum InteractionType { reveal, write }

extension CardKindName on CardKind {
  String get label => switch (this) {
        CardKind.learn => 'LEARN',
        CardKind.think => 'THINK',
        CardKind.create => 'CREATE',
        CardKind.remember => 'REMEMBER',
        CardKind.decide => 'DECIDE',
      };
}

class ImprovementCard {
  final CardKind kind;
  final String prompt;
  final int seconds;
  final InteractionType interaction;
  final String? reveal;
  final String inputHint;

  const ImprovementCard({
    required this.kind,
    required this.prompt,
    required this.seconds,
    required this.interaction,
    this.reveal,
    this.inputHint = 'Write your response...',
  });
}

const seedCards = <ImprovementCard>[
  ImprovementCard(kind: CardKind.learn, prompt: 'What does “zeitgeist” literally mean?', seconds: 20, interaction: InteractionType.reveal, reveal: '“Spirit of the time” or “spirit of the age”.'),
  ImprovementCard(kind: CardKind.learn, prompt: 'Which is larger: a billion seconds or 30 years?', seconds: 20, interaction: InteractionType.reveal, reveal: 'A billion seconds is about 31.7 years.'),
  ImprovementCard(kind: CardKind.learn, prompt: 'Why does the Moon always show us roughly the same face?', seconds: 30, interaction: InteractionType.reveal, reveal: 'Its rotation period matches its orbit around Earth. This is called tidal locking.'),
  ImprovementCard(kind: CardKind.learn, prompt: 'What is the difference between weather and climate?', seconds: 25, interaction: InteractionType.reveal, reveal: 'Weather is short-term atmospheric conditions. Climate is the long-term pattern.'),
  ImprovementCard(kind: CardKind.learn, prompt: 'What does “compound interest” mean?', seconds: 25, interaction: InteractionType.reveal, reveal: 'You earn returns on both the original amount and previously accumulated returns.'),
  ImprovementCard(kind: CardKind.think, prompt: 'What belief have you changed your mind about in the last five years?', seconds: 45, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.think, prompt: 'What would make today feel well spent by bedtime?', seconds: 30, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.think, prompt: 'What are you treating as urgent that probably is not important?', seconds: 35, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.think, prompt: 'Which opinion do you hold mostly because people around you hold it?', seconds: 45, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.create, prompt: 'Write a six-word title for the current chapter of your life.', seconds: 45, interaction: InteractionType.write, inputHint: 'Six words...'),
  ImprovementCard(kind: CardKind.create, prompt: 'Invent a better name for “doom scrolling”.', seconds: 30, interaction: InteractionType.write, inputHint: 'Your name for it...'),
  ImprovementCard(kind: CardKind.create, prompt: 'Describe a new app idea in one sentence.', seconds: 45, interaction: InteractionType.write, inputHint: 'Your app idea...'),
  ImprovementCard(kind: CardKind.create, prompt: 'Write the opening line of a story you would actually want to keep reading.', seconds: 60, interaction: InteractionType.write, inputHint: 'Opening line...'),
  ImprovementCard(kind: CardKind.remember, prompt: 'Without checking, name three things you did yesterday.', seconds: 30, interaction: InteractionType.write, inputHint: 'Three things...'),
  ImprovementCard(kind: CardKind.remember, prompt: 'Put apple, lighthouse, velvet and train into one absurd mental image. Describe it.', seconds: 30, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.remember, prompt: 'Think of the last three people you messaged. What did each conversation concern?', seconds: 35, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.remember, prompt: 'Look away from the screen. What were the last five words you read?', seconds: 20, interaction: InteractionType.write, inputHint: 'Five words...'),
  ImprovementCard(kind: CardKind.decide, prompt: 'What is one task you keep avoiding that would take less than ten minutes?', seconds: 30, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.decide, prompt: 'Choose one thing you want to know more about by this time next week.', seconds: 30, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.decide, prompt: 'What is one notification on your phone that deserves to be turned off?', seconds: 25, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.decide, prompt: 'If you could only finish one thing today, what should it be?', seconds: 30, interaction: InteractionType.write),
];

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _random = Random();
  final _answerController = TextEditingController();
  final _focusNode = FocusNode();

  ImprovementCard? _card;
  bool _revealed = false;
  Offset _drag = Offset.zero;
  int _completed = 0;
  int _skipped = 0;
  int _sessionCompleted = 0;
  int _sessionSkipped = 0;
  final Map<CardKind, int> _done = {for (final k in CardKind.values) k: 0};
  final Map<CardKind, int> _skip = {for (final k in CardKind.values) k: 0};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _answerController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    for (final k in CardKind.values) {
      _done[k] = p.getInt('done_${k.name}') ?? 0;
      _skip[k] = p.getInt('skip_${k.name}') ?? 0;
    }
    if (!mounted) return;
    setState(() {
      _completed = p.getInt('completed_total') ?? 0;
      _skipped = p.getInt('skipped_total') ?? 0;
      _card = _pick();
    });
  }

  ImprovementCard _pick() {
    final weighted = <CardKind>[];
    for (final k in CardKind.values) {
      final score = (4 + (_done[k] ?? 0) - ((_skip[k] ?? 0) ~/ 2)).clamp(1, 12);
      for (var i = 0; i < score; i++) {
        weighted.add(k);
      }
    }
    final kind = weighted[_random.nextInt(weighted.length)];
    final choices = seedCards.where((c) => c.kind == kind).toList();
    ImprovementCard next = choices[_random.nextInt(choices.length)];
    if (_card != null && choices.length > 1) {
      while (identical(next, _card)) {
        next = choices[_random.nextInt(choices.length)];
      }
    }
    return next;
  }

  Future<void> _saveResponse(ImprovementCard card, String answer) async {
    final p = await SharedPreferences.getInstance();
    final history = p.getStringList('response_history') ?? <String>[];
    history.add(jsonEncode({
      'time': DateTime.now().toIso8601String(),
      'kind': card.kind.name,
      'prompt': card.prompt,
      'answer': answer.trim(),
    }));
    if (history.length > 100) {
      history.removeRange(0, history.length - 100);
    }
    await p.setStringList('response_history', history);
  }

  Future<void> _submitResponse() async {
    final c = _card;
    if (c == null) return;
    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    await _saveResponse(c, answer);
    await _record(true);
  }

  Future<void> _record(bool completed) async {
    final c = _card;
    if (c == null) return;
    if (completed) {
      _completed++;
      _sessionCompleted++;
      _done[c.kind] = (_done[c.kind] ?? 0) + 1;
    } else {
      _skipped++;
      _sessionSkipped++;
      _skip[c.kind] = (_skip[c.kind] ?? 0) + 1;
    }

    final p = await SharedPreferences.getInstance();
    await p.setInt('completed_total', _completed);
    await p.setInt('skipped_total', _skipped);
    await p.setInt('done_${c.kind.name}', _done[c.kind] ?? 0);
    await p.setInt('skip_${c.kind.name}', _skip[c.kind] ?? 0);

    if (!mounted) return;
    _focusNode.unfocus();
    _answerController.clear();
    setState(() {
      _card = _pick();
      _revealed = false;
      _drag = Offset.zero;
    });
  }

  void _session() {
    final total = _sessionCompleted + _sessionSkipped;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This session', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            Text('$_sessionCompleted useful moments', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text('$_sessionSkipped skipped', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text(total == 0 ? 'Start with one card.' : '${((_sessionCompleted / total) * 100).round()}% of cards felt worth doing.', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 22),
            const Text('No streak. No guilt. Come back when you would otherwise scroll.'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _card;
    if (c == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final width = MediaQuery.sizeOf(context).width;
    final isWriting = c.interaction == InteractionType.write;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('instead', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  TextButton(onPressed: _session, child: Text('$_completed useful')),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onPanUpdate: isWriting && _focusNode.hasFocus ? null : (d) => setState(() => _drag += d.delta),
                    onPanEnd: isWriting && _focusNode.hasFocus
                        ? null
                        : (d) {
                            if (_drag.dy < -90 && !isWriting) {
                              _record(true);
                            } else if (_drag.dx < -90) {
                              _record(false);
                            } else {
                              setState(() => _drag = Offset.zero);
                            }
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      transform: Matrix4.identity()
                        ..translate(_drag.dx * .35, _drag.dy * .35)
                        ..rotateZ(_drag.dx / max(width, 1) * .035),
                      transformAlignment: Alignment.center,
                      child: Container(
                        width: min(width - 40, 520),
                        constraints: const BoxConstraints(minHeight: 510),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(34),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: .08), blurRadius: 30, offset: const Offset(0, 12)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.kind.label, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
                            const SizedBox(height: 8),
                            Text('about ${c.seconds} sec', style: TextStyle(color: Colors.black.withValues(alpha: .52))),
                            const Spacer(),
                            Text(
                              c.prompt,
                              style: TextStyle(
                                fontSize: isWriting ? 30 : 36,
                                height: 1.06,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.1,
                              ),
                            ),
                            if (isWriting) ...[
                              const SizedBox(height: 24),
                              TextField(
                                controller: _answerController,
                                focusNode: _focusNode,
                                minLines: 2,
                                maxLines: 5,
                                textCapitalization: TextCapitalization.sentences,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submitResponse(),
                                decoration: InputDecoration(hintText: c.inputHint),
                              ),
                            ],
                            if (c.reveal != null) ...[
                              const SizedBox(height: 24),
                              if (_revealed)
                                Text(c.reveal!, style: const TextStyle(fontSize: 18, height: 1.45))
                              else
                                FilledButton.tonal(
                                  onPressed: () => setState(() => _revealed = true),
                                  child: const Text('Reveal'),
                                ),
                            ],
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _record(false),
                                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                                    child: const Text('Skip'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton(
                                    onPressed: isWriting ? _submitResponse : () => _record(true),
                                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                                    child: Text(isWriting ? 'Submit' : 'Done'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isWriting ? 'Answer or skip  •  Swipe left: skip' : 'Swipe up: done  •  Swipe left: skip',
                style: TextStyle(color: Colors.black.withValues(alpha: .52), fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
