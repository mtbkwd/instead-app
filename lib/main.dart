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
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F6F2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF284A43), width: 1.3),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF284A43), width: 1.3),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF0A7B67), width: 2),
          ),
        ),
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
    final kind = CardKind.values.firstWhere(
      (value) => value.name == (json['kind'] ?? 'think'),
      orElse: () => CardKind.think,
    );
    final interaction = (json['interaction'] == 'reveal')
        ? InteractionType.reveal
        : InteractionType.write;

    return ImprovementCard(
      kind: kind,
      prompt: json['prompt'] as String? ?? 'What is worth thinking about right now?',
      seconds: (json['seconds'] as num?)?.toInt() ?? 30,
      interaction: interaction,
      inputHint: json['inputHint'] as String? ?? 'Write your response...',
      reveal: json['reveal'] as String?,
    );
  }
}

const fallbackCards = <ImprovementCard>[
  ImprovementCard(
    kind: CardKind.learn,
    prompt: 'Which is larger: a billion seconds or 30 years?',
    seconds: 20,
    interaction: InteractionType.write,
    inputHint: 'Your answer...',
  ),
  ImprovementCard(
    kind: CardKind.think,
    prompt: 'What would make today feel well spent by bedtime?',
    seconds: 30,
    interaction: InteractionType.write,
    inputHint: 'One thing is enough...',
  ),
  ImprovementCard(
    kind: CardKind.create,
    prompt: 'Invent a better name for doom scrolling.',
    seconds: 30,
    interaction: InteractionType.write,
  ),
  ImprovementCard(
    kind: CardKind.remember,
    prompt: 'Without checking, name three things you did yesterday.',
    seconds: 30,
    interaction: InteractionType.write,
  ),
  ImprovementCard(
    kind: CardKind.decide,
    prompt: 'If you could only finish one thing today, what should it be?',
    seconds: 30,
    interaction: InteractionType.write,
  ),
];

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  static const _remoteUrl =
      'https://raw.githubusercontent.com/mtbkwd/instead-app/main/config/cards.json';

  final Random _random = Random();
  final TextEditingController _answerController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _cardScrollController = ScrollController();

  List<ImprovementCard> _cards = fallbackCards;
  ImprovementCard? _card;
  bool _revealed = false;
  bool _refreshing = false;
  int _completed = 0;
  int _skipped = 0;
  int _sessionCompleted = 0;
  int _sessionSkipped = 0;
  int _contentVersion = 0;

  final Map<CardKind, int> _done = {for (final k in CardKind.values) k: 0};
  final Map<CardKind, int> _skip = {for (final k in CardKind.values) k: 0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _answerController.dispose();
    _focusNode.dispose();
    _cardScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_focusNode.hasFocus) {
      _refreshRemoteCards();
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    for (final kind in CardKind.values) {
      _done[kind] = prefs.getInt('done_${kind.name}') ?? 0;
      _skip[kind] = prefs.getInt('skip_${kind.name}') ?? 0;
    }

    final cached = prefs.getString('remote_cards_json');
    if (cached != null) {
      final parsed = _parseDocument(cached);
      if (parsed.cards.isNotEmpty) {
        _cards = parsed.cards;
        _contentVersion = parsed.version;
      }
    }

    if (!mounted) return;
    setState(() {
      _completed = prefs.getInt('completed_total') ?? 0;
      _skipped = prefs.getInt('skipped_total') ?? 0;
      _card = _pickCard();
    });

    await _refreshRemoteCards();
  }

  ({List<ImprovementCard> cards, int version}) _parseDocument(String source) {
    try {
      final root = jsonDecode(source) as Map<String, dynamic>;
      final raw = root['cards'] as List<dynamic>? ?? const [];
      final cards = raw
          .whereType<Map<String, dynamic>>()
          .map(ImprovementCard.fromJson)
          .where((c) => c.prompt.trim().isNotEmpty)
          .toList();
      return (cards: cards, version: (root['version'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return (cards: <ImprovementCard>[], version: 0);
    }
  }

  Future<void> _refreshRemoteCards() async {
    if (_refreshing || _focusNode.hasFocus) return;
    _refreshing = true;

    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse('$_remoteUrl?v=${DateTime.now().millisecondsSinceEpoch}');
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode != HttpStatus.ok) {
        client.close(force: true);
        return;
      }

      final source = await utf8.decoder.bind(response).join();
      client.close(force: true);
      final parsed = _parseDocument(source);
      if (parsed.cards.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('remote_cards_json', source);

      if (!mounted || _focusNode.hasFocus) return;
      setState(() {
        _cards = parsed.cards;
        _contentVersion = parsed.version;
      });
    } catch (_) {
      // Keep the cached card library when offline.
    } finally {
      _refreshing = false;
    }
  }

  ImprovementCard _pickCard() {
    if (_cards.isEmpty) return fallbackCards.first;

    final kinds = _cards.map((card) => card.kind).toSet();
    final weightedKinds = <CardKind>[];

    for (final kind in kinds) {
      final score = (4 + (_done[kind] ?? 0) - ((_skip[kind] ?? 0) ~/ 2)).clamp(1, 12);
      for (var i = 0; i < score; i++) {
        weightedKinds.add(kind);
      }
    }

    final kind = weightedKinds[_random.nextInt(weightedKinds.length)];
    final candidates = _cards.where((card) => card.kind == kind).toList();
    ImprovementCard next = candidates[_random.nextInt(candidates.length)];

    if (_card != null && candidates.length > 1) {
      var attempts = 0;
      while (next.prompt == _card!.prompt && attempts < 10) {
        next = candidates[_random.nextInt(candidates.length)];
        attempts++;
      }
    }

    return next;
  }

  Future<void> _saveResponse(ImprovementCard card, String answer) async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('response_history') ?? <String>[];

    history.add(jsonEncode({
      'time': DateTime.now().toIso8601String(),
      'kind': card.kind.name,
      'prompt': card.prompt,
      'answer': answer.trim(),
    }));

    if (history.length > 100) {
      history.removeRange(0, history.length - 100);
    }

    await prefs.setStringList('response_history', history);
  }

  Future<void> _submit() async {
    final card = _card;
    if (card == null) return;

    final answer = _answerController.text.trim();
    if (answer.isEmpty) {
      _focusNode.requestFocus();
      return;
    }

    await _saveResponse(card, answer);
    await _advance(completed: true);
  }

  Future<void> _advance({required bool completed}) async {
    final card = _card;
    if (card == null) return;

    if (completed) {
      _completed++;
      _sessionCompleted++;
      _done[card.kind] = (_done[card.kind] ?? 0) + 1;
    } else {
      _skipped++;
      _sessionSkipped++;
      _skip[card.kind] = (_skip[card.kind] ?? 0) + 1;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('completed_total', _completed);
    await prefs.setInt('skipped_total', _skipped);
    await prefs.setInt('done_${card.kind.name}', _done[card.kind] ?? 0);
    await prefs.setInt('skip_${card.kind.name}', _skip[card.kind] ?? 0);

    if (!mounted) return;

    _focusNode.unfocus();
    _answerController.clear();
    if (_cardScrollController.hasClients) {
      _cardScrollController.jumpTo(0);
    }

    setState(() {
      _revealed = false;
      _card = _pickCard();
    });
  }

  void _showSession() {
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
            Text(
              total == 0
                  ? 'Start with one card.'
                  : '${((_sessionCompleted / total) * 100).round()}% completed.',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 18),
            Text(
              'Content version $_contentVersion',
              style: TextStyle(color: Colors.black.withValues(alpha: .55)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    if (card == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final isWriting = card.interaction == InteractionType.write;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: Column(
            children: [
              // Keep this header in the tree at all times. Changing its height does
              // not change the identity or tree position of the TextField below.
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: keyboardOpen ? 0 : 52,
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: keyboardOpen ? 0 : 1,
                    child: Row(
                      children: [
                        const Text(
                          'instead',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _showSession,
                          child: Text('$_completed useful'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(keyboardOpen ? 24 : 34),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(keyboardOpen ? 16 : 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              card.kind.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'about ${card.seconds} sec',
                              style: TextStyle(color: Colors.black.withValues(alpha: .52)),
                            ),
                          ],
                        ),
                        SizedBox(height: keyboardOpen ? 10 : 28),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _cardScrollController,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  card.prompt,
                                  style: TextStyle(
                                    fontSize: keyboardOpen ? 24 : 34,
                                    height: 1.08,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1,
                                  ),
                                ),
                                if (isWriting) ...[
                                  SizedBox(height: keyboardOpen ? 14 : 24),
                                  TextField(
                                    key: const ValueKey('answer-field'),
                                    controller: _answerController,
                                    focusNode: _focusNode,
                                    autofocus: false,
                                    minLines: keyboardOpen ? 2 : 3,
                                    maxLines: keyboardOpen ? 4 : 6,
                                    textCapitalization: TextCapitalization.sentences,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    decoration: InputDecoration(hintText: card.inputHint),
                                  ),
                                ],
                                if (card.interaction == InteractionType.reveal) ...[
                                  const SizedBox(height: 20),
                                  if (_revealed && card.reveal != null)
                                    Text(card.reveal!, style: const TextStyle(fontSize: 18, height: 1.4))
                                  else
                                    FilledButton.tonal(
                                      onPressed: () => setState(() => _revealed = true),
                                      child: const Text('Reveal'),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: keyboardOpen ? 8 : 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _advance(completed: false),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: Size.fromHeight(keyboardOpen ? 46 : 52),
                                ),
                                child: const Text('Skip'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: isWriting ? _submit : () => _advance(completed: true),
                                style: FilledButton.styleFrom(
                                  minimumSize: Size.fromHeight(keyboardOpen ? 46 : 52),
                                ),
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
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: keyboardOpen ? 0 : 42,
                child: ClipRect(
                  child: Align(
                    heightFactor: keyboardOpen ? 0 : 1,
                    child: Center(
                      child: Text(
                        isWriting ? 'Answer or skip' : 'Swipe or tap to continue',
                        style: TextStyle(color: Colors.black.withValues(alpha: .5)),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
