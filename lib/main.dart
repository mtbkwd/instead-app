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
    theme: ThemeData(useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF4F1EA), colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0A7B67))),
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
  const ImprovementCard({required this.kind, required this.topic, required this.difficulty, required this.prompt, required this.seconds, required this.interaction, this.inputHint='Write your response...', this.reveal});
  factory ImprovementCard.fromJson(Map<String,dynamic> j) => ImprovementCard(
    kind: CardKind.values.firstWhere((k)=>k.name==(j['kind']??'think'), orElse:()=>CardKind.think),
    topic: j['topic'] as String? ?? (j['kind'] as String? ?? 'general'),
    difficulty: (j['difficulty'] as num?)?.toInt() ?? 1,
    prompt: j['prompt'] as String? ?? 'What is worth thinking about right now?',
    seconds: (j['seconds'] as num?)?.toInt() ?? 30,
    interaction: j['interaction']=='reveal' ? InteractionType.reveal : InteractionType.write,
    inputHint: j['inputHint'] as String? ?? 'Write your response...',
    reveal: j['reveal'] as String?,
  );
}

const fallbackCards=<ImprovementCard>[
  ImprovementCard(kind:CardKind.learn,topic:'numbers',difficulty:1,prompt:'Gut check: is a billion seconds longer or shorter than 30 years?',seconds:15,interaction:InteractionType.reveal,reveal:'Longer. A billion seconds is about 31.7 years.'),
  ImprovementCard(kind:CardKind.create,topic:'creativity',difficulty:1,prompt:'Turn a boring household object into a product someone would happily pay $100 for.',seconds:40,interaction:InteractionType.write),
  ImprovementCard(kind:CardKind.think,topic:'critical_thinking',difficulty:1,prompt:'A claim says something doubles your risk. What number do you need before deciding whether that matters?',seconds:25,interaction:InteractionType.write),
];

class FeedScreen extends StatefulWidget { const FeedScreen({super.key}); @override State<FeedScreen> createState()=>_FeedScreenState(); }
class _FeedScreenState extends State<FeedScreen> {
  static const remoteUrl='https://raw.githubusercontent.com/mtbkwd/instead-app/main/config/cards.json';
  final random=Random();
  final answerController=TextEditingController();
  final answerFocus=FocusNode();
  List<ImprovementCard> cards=fallbackCards;
  ImprovementCard? card;
  bool revealed=false;
  int completed=0, skipped=0, contentVersion=0;
  final Map<String,double> interest={};
  final Map<String,double> skill={};
  final Set<String> recentlySeen={};

  @override void initState(){ super.initState(); load(); }
  @override void dispose(){ answerController.dispose(); answerFocus.dispose(); super.dispose(); }

  Future<void> load() async {
    final p=await SharedPreferences.getInstance();
    completed=p.getInt('completed_total')??0; skipped=p.getInt('skipped_total')??0;
    _decodeMap(p.getString('interest_profile'),interest); _decodeMap(p.getString('skill_profile'),skill);
    final cached=p.getString('remote_cards_json'); if(cached!=null) applyDocument(cached);
    if(!mounted)return; setState(()=>card=pickCard()); refreshRemote();
  }
  void _decodeMap(String? s, Map<String,double> target){ if(s==null)return; try{ final m=jsonDecode(s) as Map<String,dynamic>; for(final e in m.entries){target[e.key]=(e.value as num).toDouble();}}catch(_){} }
  Future<void> _saveProfile() async { final p=await SharedPreferences.getInstance(); await p.setString('interest_profile',jsonEncode(interest)); await p.setString('skill_profile',jsonEncode(skill)); }

  void applyDocument(String source){ try{ final root=jsonDecode(source) as Map<String,dynamic>; final raw=root['cards'] as List<dynamic>? ?? const[]; final parsed=raw.whereType<Map<String,dynamic>>().map(ImprovementCard.fromJson).where((c)=>c.prompt.trim().isNotEmpty).toList(); if(parsed.isNotEmpty){cards=parsed;contentVersion=(root['version'] as num?)?.toInt()??0;}}catch(_){} }
  Future<void> refreshRemote() async { try{ final client=HttpClient()..connectionTimeout=const Duration(seconds:8); final req=await client.getUrl(Uri.parse('$remoteUrl?v=${DateTime.now().millisecondsSinceEpoch}')); req.headers.set(HttpHeaders.cacheControlHeader,'no-cache'); final res=await req.close().timeout(const Duration(seconds:10)); if(res.statusCode!=HttpStatus.ok){client.close(force:true);return;} final source=await utf8.decoder.bind(res).join(); client.close(force:true); final p=await SharedPreferences.getInstance(); await p.setString('remote_cards_json',source); applyDocument(source); if(mounted)setState((){}); }catch(_){} }

  double _weight(ImprovementCard c){
    var w=1.0;
    w*=max(.25,1+(interest[c.topic]??0)*.35);
    final level=skill[c.topic]??1;
    final gap=(c.difficulty-level).abs(); w*=max(.35,1-gap*.3);
    if(recentlySeen.contains(c.prompt))w*=.08;
    if(c.reveal!=null)w*=1.12;
    return max(.02,w);
  }
  ImprovementCard pickCard(){
    if(cards.isEmpty)return fallbackCards.first;
    final weighted=cards.map((c)=>(c,_weight(c))).toList(); final total=weighted.fold<double>(0,(s,e)=>s+e.$2); var r=random.nextDouble()*total;
    for(final e in weighted){r-=e.$2;if(r<=0){_remember(e.$1);return e.$1;}}
    _remember(cards.last); return cards.last;
  }
  void _remember(ImprovementCard c){recentlySeen.add(c.prompt);if(recentlySeen.length>7)recentlySeen.remove(recentlySeen.first);}

  Future<void> recordSignal(ImprovementCard c,{required bool useful,String answer=''}) async {
    interest[c.topic]=(interest[c.topic]??0)+(useful?1:-.45);
    if(useful && answer.trim().length>=12) skill[c.topic]=min(3.0,(skill[c.topic]??1)+.12);
    if(!useful) skill[c.topic]=max(1.0,(skill[c.topic]??1)-.03);
    final p=await SharedPreferences.getInstance(); final h=p.getStringList('response_history')??<String>[];
    h.add(jsonEncode({'time':DateTime.now().toIso8601String(),'kind':c.kind.name,'topic':c.topic,'difficulty':c.difficulty,'prompt':c.prompt,'answer':answer,'useful':useful}));
    if(h.length>200)h.removeRange(0,h.length-200); await p.setStringList('response_history',h); await _saveProfile();
  }
  Future<void> submit() async {final c=card;if(c==null)return;final a=answerController.text.trim();if(a.isEmpty)return;await recordSignal(c,useful:true,answer:a);await advance(true);}
  Future<void> advance(bool useful) async {final c=card;if(c==null)return;if(!useful)await recordSignal(c,useful:false);final p=await SharedPreferences.getInstance();if(useful)completed++;else skipped++;await p.setInt('completed_total',completed);await p.setInt('skipped_total',skipped);if(!mounted)return;answerFocus.unfocus();answerController.clear();setState((){revealed=false;card=pickCard();});}

  @override Widget build(BuildContext context){
    final c=card;if(c==null)return const Scaffold(body:Center(child:CircularProgressIndicator())); final writing=c.interaction==InteractionType.write;
    return Scaffold(resizeToAvoidBottomInset:true,body:SafeArea(child:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(24,18,24,12),child:Row(children:[const Text('instead',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const Spacer(),Text('$completed useful',style:TextStyle(color:Theme.of(context).colorScheme.primary,fontWeight:FontWeight.w700))])),
      Expanded(child:Padding(padding:const EdgeInsets.fromLTRB(20,0,20,16),child:Material(color:Colors.white,borderRadius:BorderRadius.circular(30),elevation:2,child:SingleChildScrollView(keyboardDismissBehavior:ScrollViewKeyboardDismissBehavior.manual,padding:const EdgeInsets.all(26),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Text(c.kind.label,style:TextStyle(color:Theme.of(context).colorScheme.primary,fontWeight:FontWeight.w800)),const Spacer(),Text('about ${c.seconds} sec',style:TextStyle(color:Colors.black.withValues(alpha:.5)))]),
        const SizedBox(height:28),Text(c.prompt,style:const TextStyle(fontSize:30,height:1.08,fontWeight:FontWeight.w700,letterSpacing:-1)),
        if(writing)...[const SizedBox(height:22),TextField(controller:answerController,focusNode:answerFocus,keyboardType:TextInputType.multiline,textInputAction:TextInputAction.newline,minLines:3,maxLines:6,decoration:InputDecoration(hintText:c.inputHint,filled:true,fillColor:const Color(0xFFF7F6F2),contentPadding:const EdgeInsets.all(18),border:OutlineInputBorder(borderRadius:BorderRadius.circular(18))))],
        if(c.reveal!=null)...[const SizedBox(height:20),if(revealed)Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xFFE9F5F1),borderRadius:BorderRadius.circular(18)),child:Text(c.reveal!,style:const TextStyle(fontSize:17,height:1.4)))else FilledButton.tonal(onPressed:()=>setState(()=>revealed=true),child:const Text('Reveal'))],
        const SizedBox(height:28),Row(children:[Expanded(child:OutlinedButton(onPressed:()=>advance(false),style:OutlinedButton.styleFrom(minimumSize:const Size.fromHeight(54)),child:const Text('Skip'))),const SizedBox(width:12),Expanded(child:FilledButton(onPressed:writing?submit:()=>advance(true),style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(54)),child:Text(writing?'Submit':'Useful')))]),
        const SizedBox(height:12),Center(child:Text('Personalising from what you answer and skip • content $contentVersion',textAlign:TextAlign.center,style:TextStyle(fontSize:11,color:Colors.black.withValues(alpha:.4))))
      ]))))),
    ])));
  }
}
