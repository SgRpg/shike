import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'store.dart';

class RewardCard {
 final String key,title,description;
 RewardCard(this.key,this.title,this.description);
 Map<String,String> toJson()=>{'key':key,'title':title,'description':description};
 factory RewardCard.fromJson(Map<String,dynamic> v)=>RewardCard(v['key'] as String,v['title'] as String,v['description'] as String);
}
class Rewards {
 static Future<List<RewardCard>> load() async {final p=await SharedPreferences.getInstance();return (jsonDecode(p.getString('rewards.cards')??'[]') as List).map((x)=>RewardCard.fromJson(Map<String,dynamic>.from(x))).toList();}
 static Future<List<RewardCard>> evaluate(ShikeStore store,Diary entry) async {
  final prefs=await SharedPreferences.getInstance();final cards=await load();final existing=cards.map((e)=>e.key).toSet();final added=<RewardCard>[];
  void add(String key,String title,String description){if(existing.add(key)){final card=RewardCard(key,title,description);cards.add(card);added.add(card);}}
  final days=store.completed.map((e)=>DateTime(e.created.year,e.created.month,e.created.day)).toSet();
  for(final x in [(10,'点歌卡','点一首喜欢的歌'),(14,'奶茶卡','一杯奶茶'),(30,'礼物卡','一个礼物'),(100,'大礼物卡','一份大礼物')]){if(days.length>=x.$1)add('total-${x.$1}',x.$2,x.$3);}
  var consecutive=0;var d=DateTime(entry.created.year,entry.created.month,entry.created.day);while(days.contains(d)){consecutive++;d=d.subtract(const Duration(days:1));}
  for(final x in [(7,'零食卡','一包零食'),(14,'连续礼物卡','一个礼物'),(30,'愿望卡','一个不过分的小愿望')]){if(consecutive>=x.$1)add('streak-${x.$1}',x.$2,x.$3);}
  final length=entry.text.characters.length;if(length>=500&&length<1000)add('length-500','长文卡','晚饭一次');if(length>=1000)add('length-1000','超长文卡','一份小礼物');
  if(entry.text.isNotEmpty&&entry.photos.isNotEmpty&&entry.audio!=null)add('all-media','全能卡','一次小惊喜');
  final now=DateTime.now();final week=DateTime(now.year,now.month,now.day).subtract(Duration(days:now.weekday-1));final weekKey='${week.year}-${week.month}-${week.day}';
  if(prefs.getString('rewards.randomWeek')!=weekKey&&Random().nextInt(60)==0){cards.add(RewardCard('random-${now.toIso8601String()}','被记住卡','这一刻被轻轻记住了。'));added.add(cards.last);await prefs.setString('rewards.randomWeek',weekKey);}
  await prefs.setString('rewards.cards',jsonEncode(cards.map((c)=>c.toJson()).toList()));return added;
 }
 static Future<void> show(BuildContext context,List<RewardCard> cards) async {if(cards.isEmpty||!context.mounted)return;await HapticFeedback.lightImpact();if(!context.mounted)return;final overlay=Overlay.of(context,rootOverlay:true);final first=cards.first;final entry=OverlayEntry(builder:(_)=>Positioned(left:30,right:30,bottom:90,child:Material(color:Colors.transparent,child:Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xfff5f1ea),borderRadius:BorderRadius.circular(12),boxShadow:const [BoxShadow(color:Color(0x18000000),blurRadius:10)]),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[Text(first.title,style:const TextStyle(fontSize:17,color:Color(0xff343434))),const SizedBox(height:6),Text(first.description,style:const TextStyle(color:Color(0xff899bb7)))])))));overlay.insert(entry);Future.delayed(const Duration(seconds:6),entry.remove);}
}
class CardPack extends StatefulWidget {const CardPack({super.key});@override State<CardPack> createState()=>_CardPackState();}
class _CardPackState extends State<CardPack> {
 late Future<List<RewardCard>> cards;
 @override void initState(){super.initState();cards=Rewards.load();}
 @override Widget build(BuildContext context) => Scaffold(
  appBar:AppBar(title:const Text('我的小刻痕'),centerTitle:true),
  body:FutureBuilder<List<RewardCard>>(future:cards,builder:(context,snapshot){
   if(!snapshot.hasData)return const Center(child:CircularProgressIndicator());
   final all=snapshot.data!.reversed.toList();
   if(all.isEmpty)return const Center(child:Text('还没有小刻痕。慢慢来。',style:TextStyle(color:Color(0xff899bb7))));
   return GridView.builder(padding:const EdgeInsets.all(20),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,crossAxisSpacing:12,mainAxisSpacing:12,childAspectRatio:.8),itemCount:all.length,itemBuilder:(context,i){
    final card=all[i];
    return InkWell(
     onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>RewardDetail(card:card))),
     child:Card(color:const Color(0xfff5f1ea),child:Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisAlignment:MainAxisAlignment.end,crossAxisAlignment:CrossAxisAlignment.start,children:[Text(card.title,style:const TextStyle(fontSize:18)),const SizedBox(height:8),Text(card.description,style:const TextStyle(color:Color(0xff899bb7)))]))));
   });
  }));
}
class RewardDetail extends StatelessWidget {
 final RewardCard card;
 const RewardDetail({super.key,required this.card});
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('卡片详情')),body:Center(child:Padding(padding:const EdgeInsets.all(30),child:Card(child:Padding(padding:const EdgeInsets.all(30),child:Column(mainAxisSize:MainAxisSize.min,children:[Text(card.title,style:const TextStyle(fontSize:22)),const SizedBox(height:20),Text(card.description)]))))));
}
