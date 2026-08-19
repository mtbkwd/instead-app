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
          brightness: Brightness.light,
          scaffoldBackgroundColor: const Color(0xFFF4F1EA),
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E3A34)),
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

  factory ImprovementCard.fromJson(Map<String, dynamic> json) {
    final kindName = json['kind'] as String? ?? 'think';
    final interactionName = json['interaction'] as String? ?? 'write';
    return ImprovementCard(
      kind: CardKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => CardKind.think,
      ),
      prompt: json['prompt'] as String? ?? 'What is worth thinking about right now?',
      seconds: (json['seconds'] as num?)?.toInt() ?? 30,
      interaction: interactionName == 'reveal' ? InteractionType.reveal : InteractionType.write,
      reveal: json['reveal'] as String?,
      inputHint: json['inputHint'] as String? ?? 'Write your response...',
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
    inputHint: 'Your name for it...',
  ),
  ImprovementCard(
    kind: CardKind.remember,
    prompt: 'Without checking, name three things you did yesterday.',
    seconds: 30,
    interaction: InteractionType.write,
    inputHint: 'Three things...',
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
  static const _remoteBase =
      'https://raw.githubusercontent.com/mtbkwd/instead-app/main/config/cards.json';

  final _random = Random();
  final _answerController = TextEditingController();
  final _focusNode = FocusNode();

  List<ImprovementCard> _cards = fallbackCards;
  ImprovementCard? _card;
  bool _revealed = false;
  bool _refreshing = false;
  Offset _drag = Offset.zero;
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_focusNode.hasFocus) {
      _refreshRemoteCards();
    }
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    for (final k in CardKind.values) {
      _done[k] = p.getInt('done_${k.name}') ?? 0;
      _skip[k] = p.getInt('skip_${k.name}') ?? 0;
    }

    final cached = p.getString('remote_cards_json');
    if (cached != null) {
      final parsed = _parseCardDocument(cached);
      if (parsed.cards.isNotEmpty) {
        _cards = parsed.cards;
        _contentVersion = parsed.version;
      }
    }

    if (!mounted) return;
    setState(() {
      _completed = p.getInt('completed_total') ?? 0;
      _skipped = p.getInt('skipped_total') ?? 0;
      _card = _pick();
    });

    await _refreshRemoteCards();
  }

  ({List<ImprovementCard> cards, int version}) _parseCardDocument(String source) {
    try {
      final root = jsonDecode(source) as Map<String, dynamic>;
      final rawCards = root['cards'] as List<dynamic>? ?? const [];
      final cards = rawCards
          .whereType<Map<String, dynamic>>()
          .map(ImprovementCard.fromJson)
          .where((card) => card.prompt.trim().isNotEmpty)
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
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse('$_remoteBase?v=${DateTime.now().millisecondsSinceEpoch}');
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        client.close(force: true);
        return;
      }
      final source = await utf8.decoder.bind(response).join();
      client.close(force: true);
      final parsed = _parseCardDocument(source);
      if (parsed.cards.isEmpty) return;

      final p = await SharedPreferences.getInstance();
      await p.setString('remote_cards_json', source);

      if (!mounted || _focusNode.hasFocus) return;
      final currentPrompt = _card?.prompt;
      setState(() {
        _cards = parsed.cards;
        _contentVersion = parsed.version;
        if (currentPrompt == null || !_cards.any((c) => c.prompt == currentPrompt)) {
          _card = _pick();
        }
      });
    } catch (_) {
      // Keep cached content when offline.
    } finally {
      _refreshing = false;
    }
  }

  ImprovementCard _pick() {
    if (_cards.isEmpty) return fallbackCards.first;
    final availableKinds = _cards.map((c) => c.kind).toSet();
    final weighted = <CardKind>[];
    for (final k in availableKinds) {
      final score = (4 + (_done[k] ?? 0) - ((_skip[k] ?? 0) ~/ 2)).clamp(1, 12);
      for (var i = 0; i < score; i++) {
        weighted.add(k);
      }
    }
    final kind = weighted[_random.nextInt(weighted.length)];
    final choices = _cards.where((c) => c.kind == kind).toList();
    ImprovementCard next = choices[_random.nextInt(choices.length)];
    if (_card != null && choices.length > 1) {
      var guard = 0;
      while (next.prompt == _card!.prompt && guard < 10) {
        next = choices[_random.nextInt(choices.length)];
        guard++;
      }
    }
    return next;
  }

  void _resetInteraction() {
    _focusNode.unfocus();
    _answerController.clear();
    _revealed = false;
    _drag = Offset.zero;
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
    _resetInteraction();
    setState(() {
      _card = _pick();
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
            Text(
              total == 0
                  ? 'Start with one card.'
                  : '${((_sessionCompleted / total) * 100).round()}% of cards felt worth doing.',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 22),
            Text(
              'Content version $_contentVersion. New cards load automatically when the app opens.',
              style: TextStyle(color: Colors.black.withValues(alpha: .55)),
            ),
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

    final media = MediaQuery.of(context);
    final keyboardHeight = media.viewInsets.bottom;
    final keyboardOpen = keyboardHeight > 0;
    final width = media.size.width;
    final isWriting = c.interaction == InteractionType.write;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(20, 18, 20, keyboardOpen ? keyboardHeight + 8 : 14),
          child: Column(
            children: [
              if (!keyboardOpen)
                Row(
                  children: [
                    const Text('instead', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    TextButton(onPressed: _session, child: Text('$_completed useful')),
                  ],
                ),
              if (!keyboardOpen) const SizedBox(height: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanUpdate: isWriting && _focusNode.hasFocus
                      ? null
                      : (d) => setState(() => _drag += d.delta),
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
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(keyboardOpen ? 24 : 34),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .08),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(keyboardOpen ? 18 : 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                c.kind.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'about ${c.seconds} sec',
                                style: TextStyle(color: Colors.black.withValues(alpha: .52)),
                              ),
                            ],
                          ),
                          SizedBox(height: keyboardOpen ? 10 : 22),
                          Expanded(
                            child: SingleChildScrollView(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.prompt,
                                    style: TextStyle(
                                      fontSize: keyboardOpen ? 24 : (isWriting ? 30 : 36),
                                      height: 1.06,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -1.1,
                                    ),
                                  ),
                                  if (isWriting) ...[
                                    SizedBox(height: keyboardOpen ? 14 : 24),
                                    TextField(
                                      key: ValueKey(c.prompt),
                                      controller: _answerController,
                                      focusNode: _focusNode,
                                      minLines: keyboardOpen ? 2 : 3,
                                      maxLines: keyboardOpen ? 3 : 6,
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
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: keyboardOpen ? 10 : 18),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _record(false),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: Size.fromHeight(keyboardOpen ? 44 : 52),
                                  ),
                                  child: const Text('Skip'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: isWriting ? _submitResponse : () => _record(true),
                                  style: FilledButton.styleFrom(
                                    minimumSize: Size.fromHeight(keyboardOpen ? 44 : 52),
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
              ),
              if (!keyboardOpen) ...[
                const SizedBox(height: 10),
                Text(
                  isWriting ? 'Answer or skip  •  Swipe left: skip' : 'Swipe up: done  •  Swipe left: skip',
                  style: TextStyle(color: Colors.black.withValues(alpha: .52), fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
