import 'dart:convert';
import 'dart:io';
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
      scaffoldBackgroundColor: const Color(0xFFF4F1EA),
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A7B67)),
    ),
    home: const FeedScreen(),
  );
}

enum CardKind { learn, think, create, remember, decide }
enum InteractionType { write, reveal }
extension CardKindLabel on CardKind { String get label => name.toUpperCase(); }

class ImprovementCard {
  final CardKind kind;
  final String topic;
  final int difficulty;
  final String prompt;
  final int seconds;
  final InteractionType interaction;
  final String inputHint;
  final String? reveal;

  const ImprovementCard({
    required this.kind,
    required this.topic,
    required this.difficulty,
    required this.prompt,
    required this.seconds,
    required this.interaction,
    this.inputHint = 'Write your response...',
    this.reveal,
  });

  factory ImprovementCard.fromJson(Map<String, dynamic> j) => ImprovementCard(
    kind: CardKind.values.firstWhere(
      (k) => k.name == (j['kind'] ?? 'think'),
      orElse: () => CardKind.think,
    ),
    topic: j['topic'] as String? ?? (j['kind'] as String? ?? 'general'),
    difficulty: (j['difficulty'] as num?)?.toInt() ?? 1,
    prompt: j['prompt'] as String? ?? 'What is worth thinking about right now?',
    seconds: (j['seconds'] as num?)?.toInt() ?? 30,
    interaction: j['interaction'] == 'reveal' ? InteractionType.reveal : InteractionType.write,
    inputHint: j['inputHint'] as String? ?? 'Write your response...',
    reveal: j['reveal'] as String?,
  );
}

const fallbackCards = <ImprovementCard>[
  ImprovementCard(
    kind: CardKind.learn,
    topic: 'numbers',
    difficulty: 1,
    prompt: 'Gut check: is a billion seconds longer or shorter than 30 years?',
    seconds: 15,
    interaction: InteractionType.reveal,
    reveal: 'Longer. A billion seconds is about 31.7 years.',
  ),
  ImprovementCard(
    kind: CardKind.create,
    topic: 'creativity',
    difficulty: 1,
    prompt: 'Turn a boring household object into a product someone would happily pay \$100 for.',
    seconds: 40,
    interaction: InteractionType.write,
  ),
  ImprovementCard(
    kind: CardKind.think,
    topic: 'critical_thinking',
    difficulty: 1,
    prompt: 'A claim says something doubles your risk. What number do you need before deciding whether that matters?',
    seconds: 25,
    interaction: InteractionType.write,
  ),
];

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  static const remoteUrl = 'https://raw.githubusercontent.com/mtbkwd/instead-app/main/config/cards.json';

  final random = Random();
  final answerController = TextEditingController();
  final answerFocus = FocusNode();

  List<ImprovementCard> cards = fallbackCards;
  ImprovementCard? card;
  bool revealed = false;
  bool feedbackMode = false;
  String submittedAnswer = '';
  int completed = 0;
  int skipped = 0;
  int contentVersion = 0;

  final Map<String, double> interest = {};
  final Map<String, double> skill = {};
  final Set<String> recentlySeen = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    answerController.dispose();
    answerFocus.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    completed = p.getInt('completed_total') ?? 0;
    skipped = p.getInt('skipped_total') ?? 0;
    _decodeMap(p.getString('interest_profile'), interest);
    _decodeMap(p.getString('skill_profile'), skill);
    final cached = p.getString('remote_cards_json');
    if (cached != null) applyDocument(cached);
    if (!mounted) return;
    setState(() => card = pickCard());
    refreshRemote();
  }

  void _decodeMap(String? source, Map<String, double> target) {
    if (source == null) return;
    try {
      final map = jsonDecode(source) as Map<String, dynamic>;
      for (final entry in map.entries) {
        target[entry.key] = (entry.value as num).toDouble();
      }
    } catch (_) {}
  }

  Future<void> _saveProfile() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('interest_profile', jsonEncode(interest));
    await p.setString('skill_profile', jsonEncode(skill));
  }

  void applyDocument(String source) {
    try {
      final root = jsonDecode(source) as Map<String, dynamic>;
      final raw = root['cards'] as List<dynamic>? ?? const [];
      final parsed = raw
          .whereType<Map<String, dynamic>>()
          .map(ImprovementCard.fromJson)
          .where((c) => c.prompt.trim().isNotEmpty)
          .toList();
      if (parsed.isNotEmpty) {
        cards = parsed;
        contentVersion = (root['version'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
  }

  Future<void> refreshRemote() async {
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse('$remoteUrl?v=${DateTime.now().millisecondsSinceEpoch}'));
      req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != HttpStatus.ok) {
        client.close(force: true);
        return;
      }
      final source = await utf8.decoder.bind(res).join();
      client.close(force: true);
      final p = await SharedPreferences.getInstance();
      await p.setString('remote_cards_json', source);
      applyDocument(source);
      if (mounted && !answerFocus.hasFocus && !feedbackMode) setState(() {});
    } catch (_) {}
  }

  double _weight(ImprovementCard c) {
    var weight = 1.0;
    weight *= max(.25, 1 + (interest[c.topic] ?? 0) * .35);
    final level = skill[c.topic] ?? 1;
    final gap = (c.difficulty - level).abs();
    weight *= max(.35, 1 - gap * .3);
    if (recentlySeen.contains(c.prompt)) weight *= .08;
    if (c.reveal != null) weight *= 1.12;
    return max(.02, weight);
  }

  ImprovementCard pickCard() {
    if (cards.isEmpty) return fallbackCards.first;
    final weighted = cards.map((c) => (c, _weight(c))).toList();
    final total = weighted.fold<double>(0, (sum, entry) => sum + entry.$2);
    var roll = random.nextDouble() * total;
    for (final entry in weighted) {
      roll -= entry.$2;
      if (roll <= 0) {
        _remember(entry.$1);
        return entry.$1;
      }
    }
    _remember(cards.last);
    return cards.last;
  }

  ImprovementCard pickFollowUp(ImprovementCard previous) {
    final sameTopic = cards
        .where((c) => c.topic == previous.topic && c.prompt != previous.prompt && !recentlySeen.contains(c.prompt))
        .toList();
    if (sameTopic.isEmpty) return pickCard();
    sameTopic.sort((a, b) {
      final target = min(3, previous.difficulty + 1);
      return (a.difficulty - target).abs().compareTo((b.difficulty - target).abs());
    });
    final pool = sameTopic.take(min(3, sameTopic.length)).toList();
    final next = pool[random.nextInt(pool.length)];
    _remember(next);
    return next;
  }

  void _remember(ImprovementCard c) {
    recentlySeen.add(c.prompt);
    if (recentlySeen.length > 7) recentlySeen.remove(recentlySeen.first);
  }

  Future<void> recordSignal(ImprovementCard c, {required bool useful, String answer = ''}) async {
    interest[c.topic] = (interest[c.topic] ?? 0) + (useful ? 1 : -.45);
    if (useful && answer.trim().length >= 12) {
      skill[c.topic] = min(3.0, (skill[c.topic] ?? 1) + .12);
    }
    if (!useful) {
      skill[c.topic] = max(1.0, (skill[c.topic] ?? 1) - .03);
    }
    final p = await SharedPreferences.getInstance();
    final history = p.getStringList('response_history') ?? <String>[];
    history.add(jsonEncode({
      'time': DateTime.now().toIso8601String(),
      'kind': c.kind.name,
      'topic': c.topic,
      'difficulty': c.difficulty,
      'prompt': c.prompt,
      'answer': answer,
      'useful': useful,
    }));
    if (history.length > 200) history.removeRange(0, history.length - 200);
    await p.setStringList('response_history', history);
    await _saveProfile();
  }

  Future<void> submit() async {
    final current = card;
    if (current == null) return;
    final answer = answerController.text.trim();
    if (answer.isEmpty) return;
    await recordSignal(current, useful: true, answer: answer);
    final p = await SharedPreferences.getInstance();
    completed++;
    await p.setInt('completed_total', completed);
    if (!mounted) return;
    answerFocus.unfocus();
    setState(() {
      submittedAnswer = answer;
      feedbackMode = true;
      revealed = true;
    });
  }

  Future<void> markUsefulAndContinue() async {
    final current = card;
    if (current == null) return;
    if (current.interaction == InteractionType.reveal && !feedbackMode) {
      await recordSignal(current, useful: true);
      final p = await SharedPreferences.getInstance();
      completed++;
      await p.setInt('completed_total', completed);
    }
    _nextCard(followUp: true);
  }

  Future<void> skip() async {
    final current = card;
    if (current == null) return;
    await recordSignal(current, useful: false);
    final p = await SharedPreferences.getInstance();
    skipped++;
    await p.setInt('skipped_total', skipped);
    _nextCard(followUp: false);
  }

  void _nextCard({required bool followUp}) {
    final current = card;
    if (current == null || !mounted) return;
    answerFocus.unfocus();
    answerController.clear();
    setState(() {
      revealed = false;
      feedbackMode = false;
      submittedAnswer = '';
      card = followUp ? pickFollowUp(current) : pickCard();
    });
  }

  String feedbackText(ImprovementCard c) {
    if (c.reveal != null && c.reveal!.trim().isNotEmpty) return c.reveal!;
    if (c.kind == CardKind.create) {
      return 'You made something from a blank page. That is the skill: generating an option before judging it. The next challenge will stay near ${c.topic.replaceAll('_', ' ')} and push it a little further.';
    }
    if (c.kind == CardKind.decide) {
      return 'Your answer turns an abstract problem into a concrete choice. The useful next move is to test the reasoning behind it rather than treating the first answer as final.';
    }
    if (c.kind == CardKind.think) {
      return 'You committed to a position instead of passively reading. That makes the next question more useful because it can challenge or extend your reasoning.';
    }
    if (c.kind == CardKind.remember) {
      return 'Retrieval is the exercise. Trying to reconstruct the answer strengthens memory more than rereading it.';
    }
    return 'Your answer is now part of your local learning profile. The next card will stay close to this topic and adapt the difficulty.';
  }

  @override
  Widget build(BuildContext context) {
    final current = card;
    if (current == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final writing = current.interaction == InteractionType.write;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
              child: Row(
                children: [
                  const Text('instead', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('$completed useful', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  elevation: 2,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(current.kind.label, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800)),
                            const Spacer(),
                            Text('about ${current.seconds} sec', style: TextStyle(color: Colors.black.withValues(alpha: .5))),
                          ],
                        ),
                        const SizedBox(height: 28),
                        Text(current.prompt, style: const TextStyle(fontSize: 30, height: 1.08, fontWeight: FontWeight.w700, letterSpacing: -1)),
                        if (writing && !feedbackMode) ...[
                          const SizedBox(height: 22),
                          TextField(
                            controller: answerController,
                            focusNode: answerFocus,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            minLines: 3,
                            maxLines: 6,
                            decoration: InputDecoration(
                              hintText: current.inputHint,
                              filled: true,
                              fillColor: const Color(0xFFF7F6F2),
                              contentPadding: const EdgeInsets.all(18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                          ),
                        ],
                        if (feedbackMode) ...[
                          const SizedBox(height: 20),
                          Text('Your answer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black.withValues(alpha: .5))),
                          const SizedBox(height: 6),
                          Text(submittedAnswer, style: const TextStyle(fontSize: 18, height: 1.35, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(color: const Color(0xFFE9F5F1), borderRadius: BorderRadius.circular(18)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Why this matters', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 8),
                                Text(feedbackText(current), style: const TextStyle(fontSize: 17, height: 1.4)),
                              ],
                            ),
                          ),
                        ] else if (current.reveal != null) ...[
                          const SizedBox(height: 20),
                          if (revealed)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(color: const Color(0xFFE9F5F1), borderRadius: BorderRadius.circular(18)),
                              child: Text(current.reveal!, style: const TextStyle(fontSize: 17, height: 1.4)),
                            )
                          else
                            FilledButton.tonal(onPressed: () => setState(() => revealed = true), child: const Text('Reveal')),
                        ],
                        const SizedBox(height: 28),
                        if (feedbackMode)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: markUsefulAndContinue,
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                              child: Text('Another ${current.topic.replaceAll('_', ' ')} challenge'),
                            ),
                          )
                        else
                          Row(
                            children: [
                              Expanded(child: OutlinedButton(onPressed: skip, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)), child: const Text('Skip'))),
                              const SizedBox(width: 12),
                              Expanded(child: FilledButton(onPressed: writing ? submit : markUsefulAndContinue, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)), child: Text(writing ? 'Submit' : 'Useful'))),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Personalising from what you answer and skip • content $contentVersion',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: .4)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
