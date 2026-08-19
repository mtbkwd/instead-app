import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const InsteadApp());

class InsteadApp extends StatelessWidget {
  const InsteadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
}

enum CardKind { learn, think, create, remember, decide }
enum InteractionType { write, reveal }

extension CardKindLabel on CardKind {
  String get label => name.toUpperCase();
}

class ImprovementCard {
  final CardKind kind;
  final String prompt;
  final int seconds;
  final InteractionType interaction;
  final String inputHint;
  final String? reveal;

  const ImprovementCard({
    required this.kind,
    required this.prompt,
    required this.seconds,
    required this.interaction,
    this.inputHint = 'Write your response...',
    this.reveal,
  });

  factory ImprovementCard.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'think';
    return ImprovementCard(
      kind: CardKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => CardKind.think,
      ),
      prompt: json['prompt'] as String? ?? 'What is worth thinking about right now?',
      seconds: (json['seconds'] as num?)?.toInt() ?? 30,
      interaction: json['interaction'] == 'reveal'
          ? InteractionType.reveal
          : InteractionType.write,
      inputHint: json['inputHint'] as String? ?? 'Write your response...',
      reveal: json['reveal'] as String?,
    );
  }
}

const fallbackCards = <ImprovementCard>[
  ImprovementCard(kind: CardKind.learn, prompt: 'Which is larger: a billion seconds or 30 years?', seconds: 20, interaction: InteractionType.write, inputHint: 'Your answer...'),
  ImprovementCard(kind: CardKind.think, prompt: 'What would make today feel well spent by bedtime?', seconds: 30, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.create, prompt: 'Invent a better name for doom scrolling.', seconds: 30, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.remember, prompt: 'Without checking, name three things you did yesterday.', seconds: 30, interaction: InteractionType.write),
  ImprovementCard(kind: CardKind.decide, prompt: 'If you could only finish one thing today, what should it be?', seconds: 30, interaction: InteractionType.write),
];

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  static const remoteUrl = 'https://raw.githubusercontent.com/mtbkwd/instead-app/main/config/cards.json';

  final random = Random();
  final answerController = TextEditingController();
  final answerFocus = FocusNode(debugLabel: 'answer');
  final diagnostic = ValueNotifier<String>('diagnostic ready');

  List<ImprovementCard> cards = fallbackCards;
  ImprovementCard? card;
  bool revealed = false;
  int completed = 0;
  int skipped = 0;
  int contentVersion = 0;
  int buildCount = 0;

  void logEvent(String event) {
    final now = DateTime.now();
    final stamp = '${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}.${now.millisecond.toString().padLeft(3, '0')}';
    final previous = diagnostic.value.split('\n').take(5).join('\n');
    diagnostic.value = '$stamp  $event\n$previous';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    answerFocus.addListener(() {
      logEvent(answerFocus.hasFocus ? 'FOCUS gained' : 'FOCUS LOST');
    });
    logEvent('initState');
    load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    answerController.dispose();
    answerFocus.dispose();
    diagnostic.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    logEvent('lifecycle ${state.name}');
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final bottom = view.viewInsets.bottom / view.devicePixelRatio;
    logEvent('metrics keyboard=${bottom.round()}px');
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    completed = prefs.getInt('completed_total') ?? 0;
    skipped = prefs.getInt('skipped_total') ?? 0;
    final cached = prefs.getString('remote_cards_json');
    if (cached != null) applyDocument(cached);
    if (!mounted) return;
    setState(() => card = pickCard());
    logEvent('initial card set');
    refreshRemote();
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
    logEvent('remote refresh START');
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(Uri.parse('$remoteUrl?v=${DateTime.now().millisecondsSinceEpoch}'));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        client.close(force: true);
        logEvent('remote HTTP ${response.statusCode}');
        return;
      }
      final source = await utf8.decoder.bind(response).join();
      client.close(force: true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('remote_cards_json', source);
      applyDocument(source);
      logEvent('remote refresh APPLY focus=${answerFocus.hasFocus}');
      if (mounted) setState(() {});
    } catch (_) {
      logEvent('remote refresh ERROR');
    }
  }

  ImprovementCard pickCard() {
    if (cards.isEmpty) return fallbackCards.first;
    return cards[random.nextInt(cards.length)];
  }

  Future<void> saveResponse(ImprovementCard current, String answer) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('response_history') ?? <String>[];
    history.add(jsonEncode({
      'time': DateTime.now().toIso8601String(),
      'kind': current.kind.name,
      'prompt': current.prompt,
      'answer': answer,
    }));
    if (history.length > 100) history.removeRange(0, history.length - 100);
    await prefs.setStringList('response_history', history);
  }

  Future<void> submit() async {
    final current = card;
    if (current == null) return;
    final answer = answerController.text.trim();
    if (answer.isEmpty) return;
    await saveResponse(current, answer);
    await advance(true);
  }

  Future<void> advance(bool wasCompleted) async {
    final prefs = await SharedPreferences.getInstance();
    if (wasCompleted) {
      completed++;
    } else {
      skipped++;
    }
    await prefs.setInt('completed_total', completed);
    await prefs.setInt('skipped_total', skipped);
    if (!mounted) return;
    answerFocus.unfocus();
    answerController.clear();
    setState(() {
      revealed = false;
      card = pickCard();
    });
  }

  @override
  Widget build(BuildContext context) {
    buildCount++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) logEvent('build #$buildCount focus=${answerFocus.hasFocus}');
    });

    final current = card;
    if (current == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final isWriting = current.interaction == InteractionType.write;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
              child: Row(
                children: [
                  const Text('instead', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('$completed useful', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ValueListenableBuilder<String>(
                valueListenable: diagnostic,
                builder: (context, value, _) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 10, height: 1.15, fontFamily: 'monospace')),
                ),
              ),
            ),
            const SizedBox(height: 8),
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
                        if (isWriting) ...[
                          const SizedBox(height: 22),
                          TextField(
                            controller: answerController,
                            focusNode: answerFocus,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            minLines: 3,
                            maxLines: 6,
                            onTap: () => logEvent('TextField TAP'),
                            onChanged: (value) => logEvent('TEXT changed len=${value.length}'),
                            decoration: InputDecoration(
                              hintText: current.inputHint,
                              filled: true,
                              fillColor: const Color(0xFFF7F6F2),
                              contentPadding: const EdgeInsets.all(18),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                          ),
                        ],
                        if (current.reveal != null) ...[
                          const SizedBox(height: 24),
                          if (revealed)
                            Text(current.reveal!, style: const TextStyle(fontSize: 18, height: 1.4))
                          else
                            FilledButton.tonal(onPressed: () => setState(() => revealed = true), child: const Text('Reveal')),
                        ],
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(child: OutlinedButton(onPressed: () => advance(false), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)), child: const Text('Skip'))),
                            const SizedBox(width: 12),
                            Expanded(child: FilledButton(onPressed: isWriting ? submit : () => advance(true), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)), child: Text(isWriting ? 'Submit' : 'Done'))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Center(child: Text('diagnostic build • content $contentVersion', style: TextStyle(fontSize: 11, color: Colors.black.withValues(alpha: .35)))),
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
