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
    ),
    home: const FeedScreen(),
  );
}

enum CardKind { learn, think, create, remember, decide }

extension CardKindName on CardKind {
  String get label => switch (this) {
    CardKind.learn => 'LEARN', CardKind.think => 'THINK',
    CardKind.create => 'CREATE', CardKind.remember => 'REMEMBER',
    CardKind.decide => 'DECIDE',
  };
}

class ImprovementCard {
  final CardKind kind;
  final String prompt;
  final String? reveal;
  final int seconds;
  const ImprovementCard(this.kind, this.prompt, this.seconds, [this.reveal]);
}

const seedCards = <ImprovementCard>[
  ImprovementCard(CardKind.learn, 'What does “zeitgeist” literally mean?', 20, '“Spirit of the time” or “spirit of the age”.'),
  ImprovementCard(CardKind.learn, 'Which is larger: a billion seconds or 30 years?', 20, 'A billion seconds is about 31.7 years.'),
  ImprovementCard(CardKind.learn, 'Why does the Moon always show us roughly the same face?', 30, 'Its rotation period matches its orbit around Earth. This is called tidal locking.'),
  ImprovementCard(CardKind.learn, 'What is the difference between weather and climate?', 25, 'Weather is short-term atmospheric conditions. Climate is the long-term pattern.'),
  ImprovementCard(CardKind.learn, 'What does “compound interest” mean?', 25, 'You earn returns on both the original amount and previously accumulated returns.'),
  ImprovementCard(CardKind.think, 'What belief have you changed your mind about in the last five years?', 45),
  ImprovementCard(CardKind.think, 'What would make today feel well spent by bedtime?', 30),
  ImprovementCard(CardKind.think, 'What are you treating as urgent that probably is not important?', 35),
  ImprovementCard(CardKind.think, 'Which opinion do you hold mostly because people around you hold it?', 45),
  ImprovementCard(CardKind.create, 'Write a six-word title for the current chapter of your life.', 45),
  ImprovementCard(CardKind.create, 'Invent a better name for “doom scrolling”.', 30),
  ImprovementCard(CardKind.create, 'Describe a new app idea in one sentence.', 45),
  ImprovementCard(CardKind.create, 'Write the opening line of a story you would actually want to keep reading.', 60),
  ImprovementCard(CardKind.remember, 'Without checking, name three things you did yesterday.', 30),
  ImprovementCard(CardKind.remember, 'Put apple, lighthouse, velvet and train into one absurd mental image.', 30),
  ImprovementCard(CardKind.remember, 'Think of the last three people you messaged. What did each conversation concern?', 35),
  ImprovementCard(CardKind.remember, 'Look away from the screen. What were the last five words you read?', 20),
  ImprovementCard(CardKind.decide, 'What is one task you keep avoiding that would take less than ten minutes?', 30),
  ImprovementCard(CardKind.decide, 'Choose one thing you want to know more about by this time next week.', 30),
  ImprovementCard(CardKind.decide, 'What is one notification on your phone that deserves to be turned off?', 25),
  ImprovementCard(CardKind.decide, 'If you could only finish one thing today, what should it be?', 30),
];

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _random = Random();
  ImprovementCard? _card;
  bool _revealed = false;
  Offset _drag = Offset.zero;
  int _completed = 0, _skipped = 0, _sessionCompleted = 0, _sessionSkipped = 0;
  final Map<CardKind,int> _done = {for (final k in CardKind.values) k:0};
  final Map<CardKind,int> _skip = {for (final k in CardKind.values) k:0};

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    for (final k in CardKind.values) {
      _done[k] = p.getInt('done_${k.name}') ?? 0;
      _skip[k] = p.getInt('skip_${k.name}') ?? 0;
    }
    if (!mounted) return;
    setState(() { _completed=p.getInt('completed_total')??0; _skipped=p.getInt('skipped_total')??0; _card=_pick(); });
  }

  ImprovementCard _pick() {
    final weighted=<CardKind>[];
    for(final k in CardKind.values){
      final score=(4+(_done[k]??0)-((_skip[k]??0)~/2)).clamp(1,12);
      for(var i=0;i<score;i++) weighted.add(k);
    }
    final kind=weighted[_random.nextInt(weighted.length)];
    final choices=seedCards.where((c)=>c.kind==kind).toList();
    ImprovementCard next=choices[_random.nextInt(choices.length)];
    if(_card!=null&&choices.length>1){while(identical(next,_card)){next=choices[_random.nextInt(choices.length)];}}
    return next;
  }

  Future<void> _record(bool completed) async {
    final c=_card; if(c==null)return;
    if(completed){_completed++;_sessionCompleted++;_done[c.kind]=(_done[c.kind]??0)+1;}
    else{_skipped++;_sessionSkipped++;_skip[c.kind]=(_skip[c.kind]??0)+1;}
    final p=await SharedPreferences.getInstance();
    await p.setInt('completed_total',_completed); await p.setInt('skipped_total',_skipped);
    await p.setInt('done_${c.kind.name}',_done[c.kind]??0); await p.setInt('skip_${c.kind.name}',_skip[c.kind]??0);
    if(!mounted)return; setState((){_card=_pick();_revealed=false;_drag=Offset.zero;});
  }

  void _session(){
    final total=_sessionCompleted+_sessionSkipped;
    showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(context)=>Padding(
      padding:const EdgeInsets.fromLTRB(24,8,24,30), child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('This session',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),const SizedBox(height:18),
        Text('$_sessionCompleted useful moments',style:const TextStyle(fontSize:18)),const SizedBox(height:8),
        Text('$_sessionSkipped skipped',style:const TextStyle(fontSize:18)),const SizedBox(height:8),
        Text(total==0?'Start with one card.':'${((_sessionCompleted/total)*100).round()}% of cards felt worth doing.',style:const TextStyle(fontSize:18)),
        const SizedBox(height:22),const Text('No streak. No guilt. Come back when you would otherwise scroll.'),
      ]),));
  }

  @override Widget build(BuildContext context){
    final c=_card; if(c==null)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final width=MediaQuery.sizeOf(context).width;
    return Scaffold(body:SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
      Row(children:[const Text('instead',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const Spacer(),TextButton(onPressed:_session,child:Text('$_completed useful'))]),
      const SizedBox(height:18),
      Expanded(child:Center(child:GestureDetector(
        onPanUpdate:(d)=>setState(()=>_drag+=d.delta),
        onPanEnd:(d){if(_drag.dy < -90){_record(true);}else if(_drag.dx < -90){_record(false);}else{setState(()=>_drag=Offset.zero);}},
        child:AnimatedContainer(duration:const Duration(milliseconds:140),transform:Matrix4.identity()..translate(_drag.dx*.35,_drag.dy*.35)..rotateZ(_drag.dx/max(width,1)*.035),transformAlignment:Alignment.center,
          child:Container(width:min(width-40,520),constraints:const BoxConstraints(minHeight:510),padding:const EdgeInsets.all(28),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(34),boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.08),blurRadius:30,offset:const Offset(0,12))]),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(c.kind.label,style:TextStyle(fontWeight:FontWeight.w700,color:Theme.of(context).colorScheme.primary)),const SizedBox(height:10),
            Text('about ${c.seconds} sec',style:TextStyle(color:Colors.black.withValues(alpha:.52))),const Spacer(),
            Text(c.prompt,style:const TextStyle(fontSize:38,height:1.04,fontWeight:FontWeight.w700,letterSpacing:-1.3)),
            if(c.reveal!=null)...[const SizedBox(height:30),if(_revealed)Text(c.reveal!,style:const TextStyle(fontSize:18,height:1.45))else FilledButton.tonal(onPressed:()=>setState(()=>_revealed=true),child:const Text('Reveal'))],
            const Spacer(),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>_record(false),style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(52)),child:const Text('Skip'))),const SizedBox(width:12),Expanded(child:FilledButton(onPressed:()=>_record(true),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(52)),child:const Text('Done')))]),
          ])),
        ),
      ))),const SizedBox(height:14),Text('Swipe up: done   •   Swipe left: skip',style:TextStyle(color:Colors.black.withValues(alpha:.52),fontSize:13)),
    ]))));
  }
}
