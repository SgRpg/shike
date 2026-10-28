import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'store.dart';
import 'media.dart';
import 'rewards.dart';
import 'notifications.dart';
import 'backup.dart';

const bg = Color(0xfffaf9f6);
const ink = Color(0xff222329);
const muted = Color(0xff899bb7);
const moodColors = [Color(0xff92a8bb), Color(0xffa2b8df), Color(0xffd5dcdf), Color(0xffddc4b5), Color(0xffffc3a9), Color(0xffe29a83)];
String day(DateTime d) => DateFormat('M月d日').format(d);
String date(DateTime d) => DateFormat('yyyy.MM.dd').format(d);
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

Future<void> gentleCard(BuildContext context) async {
 final raw=await rootBundle.loadString('assets/phrases.json');
 final all=List<String>.from((jsonDecode(raw) as Map<String,dynamic>)['low'] as List);
 final prefs=await SharedPreferences.getInstance();final recent=prefs.getStringList('gentle.recent')??[];
 final available=all.where((x)=>!recent.contains(x)).toList();final phrase=available[Random().nextInt(available.length)];
 await prefs.setStringList('gentle.recent',[phrase,...recent].take(5).toList());
 if(!context.mounted)return;final overlay=Overlay.of(context,rootOverlay:true);
 final entry=OverlayEntry(builder:(_)=>IgnorePointer(child:Center(child:Material(color:Colors.transparent,child:Container(margin:const EdgeInsets.symmetric(horizontal:35),padding:const EdgeInsets.symmetric(horizontal:24,vertical:18),decoration:BoxDecoration(color:const Color(0xeef5f1ea),borderRadius:BorderRadius.circular(16)),child:Text(phrase,textAlign:TextAlign.center,style:const TextStyle(color:ink,fontSize:16)))))));
 overlay.insert(entry);Timer(const Duration(milliseconds:2500),entry.remove);
}

class ShikeApp extends StatelessWidget {
  final ShikeStore store;
  const ShikeApp({super.key, required this.store});
  @override Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner:false, title:'拾刻',
    theme:ThemeData(useMaterial3:true, scaffoldBackgroundColor:bg, colorScheme:ColorScheme.fromSeed(seedColor:ink, surface:bg),
      fontFamilyFallback:const ['PingFang SC','Microsoft YaHei'], textTheme:const TextTheme(bodyMedium:TextStyle(color:ink,fontSize:16))),
    home:Home(store:store));
}
class Home extends StatefulWidget {
  final ShikeStore store;
  const Home({super.key, required this.store});
  @override State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home> with WidgetsBindingObserver {
  int tab=0; Timer? refresh;
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);refresh=Timer.periodic(const Duration(seconds:30),(_){if(mounted)setState((){});});}
  @override void didChangeAppLifecycleState(AppLifecycleState state){if(state==AppLifecycleState.resumed&&mounted)setState((){});}
  @override void dispose(){refresh?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override Widget build(BuildContext c) => AnimatedBuilder(animation:widget.store,builder:(c,_)=>Scaffold(
    body:SafeArea(child:IndexedStack(index:tab,children:[Today(store:widget.store),Timeline(store:widget.store),
      Heart(store:widget.store),Corner(store:widget.store)])),
    bottomNavigationBar:NavigationBar(backgroundColor:bg,indicatorColor:Colors.transparent,selectedIndex:tab,
      onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [
        NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'此刻'),
        NavigationDestination(icon:Icon(Icons.article_outlined),selectedIcon:Icon(Icons.article),label:'拾光'),
        NavigationDestination(icon:Icon(Icons.favorite_border),selectedIcon:Icon(Icons.favorite),label:'心迹'),
        NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'角落')])));
}
class MoodDots extends StatelessWidget {
  final int? selected; final ValueChanged<int> onChanged;
  const MoodDots({super.key,required this.selected,required this.onChanged});
  @override Widget build(BuildContext c)=>Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:List.generate(6,(i)=>
    Semantics(label:'心情 $i 分',selected:selected==i,button:true,child:InkWell(onTap:()=>onChanged(i),borderRadius:BorderRadius.circular(30),
      child:Container(width:42,height:44,alignment:Alignment.center,child:Container(width:22+i*1.2,height:22+i*1.2,
        decoration:BoxDecoration(color:moodColors[i],shape:BoxShape.circle,border:selected==i?Border.all(color:Colors.white,width:3):null,
          boxShadow:selected==i?[const BoxShadow(color:Color(0x30000000),blurRadius:4)]:null)))))));
}
class Heading extends StatelessWidget { final String title; const Heading(this.title,{super.key});
 @override Widget build(BuildContext c)=>Text(title,style:const TextStyle(fontSize:30,fontWeight:FontWeight.w700,letterSpacing:1,color:ink)); }
class Today extends StatefulWidget {final ShikeStore store;const Today({super.key,required this.store});@override State<Today> createState()=>_TodayState();}
class _TodayState extends State<Today> {
 final text=TextEditingController(); int? mood;
 @override void dispose(){text.dispose();super.dispose();}
 Future<void> save() async {final now=DateTime.now();final savedMood=mood!;final e=Diary(id:widget.store.newId(),text:text.text.trim(),mood:mood,created:now,updated:now,state:'done');await widget.store.save(e);final cards=await Rewards.evaluate(widget.store,e);text.clear();setState(()=>mood=null);if(savedMood<=2 && mounted)await gentleCard(context);if(mounted)await Rewards.show(context,cards);}
 @override Widget build(BuildContext c)=>SingleChildScrollView(padding:const EdgeInsets.fromLTRB(24,18,24,20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   const Heading('拾刻'),const SizedBox(height:8),Text(day(DateTime.now()),style:const TextStyle(color:muted)),const SizedBox(height:38),
   TextField(controller:text,onChanged:(_)=>setState((){}),decoration:const InputDecoration(hintText:'这一刻，有什么想留下的？',hintStyle:TextStyle(color:muted),
     enabledBorder:UnderlineInputBorder(borderSide:BorderSide(color:Color(0xffd6e0eb))),focusedBorder:UnderlineInputBorder(borderSide:BorderSide(color:muted)))),
   const SizedBox(height:20),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('心情'),TextButton(onPressed:text.text.trim().isNotEmpty && mood!=null?save:null,child:const Text('收好'))]),
   MoodDots(selected:mood,onChanged:(v)=>setState(()=>mood=v)),const SizedBox(height:45),
   EntryRow(icon:Icons.edit_outlined,title:'写日记',subtitle:widget.store.drafts.isEmpty?'慢慢写下来':'${widget.store.drafts.length} 篇未完成',onTap:()=>openDrafts(c,widget.store)),
   const Divider(height:1,color:Color(0xffe9e8e5)),
   EntryRow(icon:Icons.mail_outline,title:'时间胶囊',subtitle:'给未来写封信',onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>Editor(store:widget.store,capsule:true))))]));
}
class EntryRow extends StatelessWidget {final IconData icon;final String title,subtitle;final VoidCallback onTap;const EntryRow({super.key,required this.icon,required this.title,required this.subtitle,required this.onTap});
 @override Widget build(BuildContext c)=>ListTile(contentPadding:EdgeInsets.zero,leading:Icon(icon,size:29,color:ink),title:Text(title,style:const TextStyle(fontSize:20)),subtitle:Text(subtitle,style:const TextStyle(color:muted,fontSize:13)),trailing:const Icon(Icons.chevron_right,size:20),onTap:onTap);}
void openDrafts(BuildContext c,ShikeStore store) { if(store.drafts.isEmpty){Navigator.push(c,MaterialPageRoute(builder:(_)=>Editor(store:store)));}else{Navigator.push(c,MaterialPageRoute(builder:(_)=>Drafts(store:store)));} }
class Drafts extends StatelessWidget { final ShikeStore store;const Drafts({super.key,required this.store});
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('未完成'),actions:[IconButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>Editor(store:store))),icon:const Icon(Icons.add))]),body:AnimatedBuilder(animation:store,builder:(c,_)=>ListView(children:store.drafts.map((d)=>ListTile(title:Text(d.text.isEmpty?'空白日记':d.text,maxLines:1,overflow:TextOverflow.ellipsis),subtitle:Text('${d.capsuleDraft?'时间胶囊 · ':''}${date(d.updated)}'),onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>Editor(store:store,draft:d,capsule:d.capsuleDraft))),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:() async {final yes=await showDialog<bool>(context:c,builder:(c)=>AlertDialog(title:const Text('丢弃这篇草稿？'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('取消')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('丢弃'))]));if(yes==true)await store.deleteDraft(d.id);}))).toList())));}

class Timeline extends StatelessWidget { final ShikeStore store; const Timeline({super.key,required this.store});
 @override Widget build(BuildContext c){final list=store.entries.where((e)=>e.state!='draft').toList();return Padding(padding:const EdgeInsets.fromLTRB(24,18,24,0),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Heading('拾光'),IconButton(onPressed:()=>showSearch(context:c,delegate:DiarySearch(store)),icon:const Icon(Icons.search))]),
   const SizedBox(height:20),Expanded(child:list.isEmpty?const Center(child:Text('还没有拾起什么。今天想留一句吗？',style:TextStyle(color:muted))):ListView.separated(itemCount:list.length,separatorBuilder:(_,_)=>const Divider(height:30,color:Color(0xffe9e8e5)),itemBuilder:(c,i){final e=list[i];return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text(day(e.created),style:const TextStyle(color:muted)),const SizedBox(height:12),e.lockedCapsule?Container(width:double.infinity,padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:const Color(0xfff5f1ea),borderRadius:BorderRadius.circular(9)),child:Row(children:[const Icon(Icons.mail_outline,size:30),const SizedBox(width:18),Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('时间胶囊',style:TextStyle(fontSize:18)),Text(capsuleText(e.unlockAt!),style:const TextStyle(color:Color(0xffbbb6b0),fontSize:13))])])):
     InkWell(onTap:()=>openDiary(c,e),child:Row(children:[Expanded(child:Text(e.text,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:17))),if(e.mood!=null)CircleAvatar(radius:8,backgroundColor:moodColors[e.mood!]),const SizedBox(width:12),const Icon(Icons.chevron_right)]))]);}))]));}
}
String capsuleText(DateTime until){final d=until.difference(DateTime.now());if(d.inDays>=2)return '${d.inDays} 天后再来看看呀';if(d.inHours>=24)return '明天再来看呀';if(d.inHours>=1)return '${d.inHours} 小时后再来看看呀';return '快要可以打开喽';}
void openDiary(BuildContext c,Diary e)=>Navigator.push(c,MaterialPageRoute(builder:(_)=>DiaryDetail(entry:e)));
class DiaryDetail extends StatelessWidget {final Diary entry;const DiaryDetail({super.key,required this.entry});
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(backgroundColor:bg),body:ListView(padding:const EdgeInsets.all(24),children:[
 if(entry.state=='capsule')Center(child:Text('来自 ${date(entry.created)} 的你',style:const TextStyle(color:muted))),const SizedBox(height:20),Text(date(entry.created),style:const TextStyle(color:muted)),const SizedBox(height:35),Text(entry.text,style:const TextStyle(fontSize:18,height:1.7)),const SizedBox(height:24),if(entry.photos.isNotEmpty)Wrap(spacing:8,runSpacing:8,children:entry.photos.map((p)=>SizedBox(width:100,height:100,child:storedImage(p))).toList()),if(entry.audio!=null)AudioControl(file:entry.audio!),const SizedBox(height:40),const Center(child:Text('拾刻',style:TextStyle(color:muted)))]));}
class AudioControl extends StatefulWidget {final String file;const AudioControl({super.key,required this.file});@override State<AudioControl> createState()=>_AudioControlState();}
class _AudioControlState extends State<AudioControl> {final player=AudioPlayer();@override void dispose(){player.dispose();super.dispose();}@override Widget build(BuildContext c)=>TextButton.icon(onPressed:()=>player.play(DeviceFileSource(widget.file)),icon:const Icon(Icons.play_arrow),label:const Text('播放语音'));}
class DiarySearch extends SearchDelegate<void> {final ShikeStore store;DiarySearch(this.store);@override String get searchFieldLabel=>'搜索日记';
 @override List<Widget> buildActions(BuildContext c)=>[IconButton(onPressed:()=>query='',icon:const Icon(Icons.close))];@override Widget buildLeading(BuildContext c)=>BackButton(onPressed:()=>close(c,null));
 @override Widget buildResults(BuildContext c)=>_results();@override Widget buildSuggestions(BuildContext c)=>_results();
 Widget _results()=>Builder(builder:(c){final matches=query.trim().isEmpty?<Diary>[]:store.completed.where((d)=>d.text.contains(query.trim())).toList();return ListView(children:matches.map((e)=>ListTile(title:Text(e.text,maxLines:2),subtitle:Text(date(e.created)),onTap:()=>openDiary(c,e))).toList());});}

class Editor extends StatefulWidget {final ShikeStore store;final Diary? draft;final bool capsule;const Editor({super.key,required this.store,this.draft,this.capsule=false});
 @override State<Editor> createState()=>_EditorState();}
class _EditorState extends State<Editor> {
 late final TextEditingController text;late final String id;late final DateTime created;late final List<String> photos;final recorder=AudioRecorder();String? audio;bool recording=false;Timer? recordingTimer;int? mood;bool showMoods=false;bool focus=false;bool completed=false;bool canExit=false;bool exiting=false;Timer? timer;Future<void> pending=Future.value();
 @override void initState(){super.initState();id=widget.draft?.id??widget.store.newId();created=widget.draft?.created??DateTime.now();mood=widget.draft?.mood;photos=List.of(widget.draft?.photos??[]);audio=widget.draft?.audio;text=TextEditingController(text:widget.draft?.text??'');text.addListener(changed);}
 void changed(){if(!mounted)return;setState((){});timer?.cancel();timer=Timer(const Duration(milliseconds:600),()=>saveDraft());}
 Future<void> saveDraft() {if(completed || (text.text.trim().isEmpty && mood==null && photos.isEmpty && audio==null && widget.draft==null))return pending;final entry=Diary(id:id,text:text.text,mood:mood,created:created,updated:DateTime.now(),state:'draft',photos:List.of(photos),audio:audio,capsuleDraft:widget.capsule);pending=pending.then((_)=>widget.store.save(entry));return pending;}
 Future<void> addPhotos() async {try {final files=await ImagePicker().pickMultiImage();for(final file in files){photos.add(await copyImage(file));}await saveDraft();if(mounted)setState((){});}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('无法导入照片，请检查相册权限。')));}}
 Future<void> recordAudio() async {if(kIsWeb){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('语音录制请在 iPhone 上使用')));return;}try {if(recording){await stopAudio();return;}if(!await recorder.hasPermission()){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('请允许麦克风权限')));return;}final dir=await getApplicationDocumentsDirectory();final filename=path.join(dir.path,'voice-$id-${DateTime.now().millisecondsSinceEpoch}.m4a');await recorder.start(const RecordConfig(encoder:AudioEncoder.aacLc),path:filename);recording=true;if(mounted)setState((){});recordingTimer=Timer(const Duration(seconds:10),stopAudio);}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('无法录制语音')));}}
 Future<void> stopAudio() async {if(!recording)return;recording=false;recordingTimer?.cancel();final file=await recorder.stop();if(file!=null)audio=file;await saveDraft();if(mounted)setState((){});}
 @override void dispose(){timer?.cancel();recordingTimer?.cancel();recorder.dispose();text.removeListener(changed);text.dispose();super.dispose();}
 Future<void> goBack() async {if(exiting)return;exiting=true;timer?.cancel();await stopAudio();await saveDraft();if(mounted){setState(()=>canExit=true);WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)Navigator.pop(context);});}}
 Future<void> finish() async {if(text.text.trim().isEmpty || mood==null)return;timer?.cancel();await stopAudio();await saveDraft();if(!mounted)return;
  DateTime? unlock;
  if(widget.capsule){final d=await showDatePicker(context:context,firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:3652)),initialDate:DateTime.now().add(const Duration(days:1)));if(d==null||!mounted)return;final t=await showTimePicker(context:context,initialTime:TimeOfDay.now());if(t==null||!mounted)return;unlock=DateTime(d.year,d.month,d.day,t.hour,t.minute);if(unlock.difference(DateTime.now())<const Duration(hours:1)){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('请选择至少 1 小时后的时间')));return;}}
  if(!mounted)return;final ok=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>Preview(text:text.text,mood:mood!,created:created,unlock:unlock,photos:List.of(photos),audio:audio)));
  if(ok==true){await pending;completed=true;final e=Diary(id:id,text:text.text.trim(),mood:mood,created:created,updated:DateTime.now(),state:widget.capsule?'capsule':'done',unlockAt:unlock,photos:List.of(photos),audio:audio);await widget.store.save(e);if(widget.capsule)await CapsuleNotifications.schedule(e);final cards=widget.capsule?<RewardCard>[]:await Rewards.evaluate(widget.store,e);if(mounted && !widget.capsule && mood!<=2)await gentleCard(context);if(mounted)await Rewards.show(context,cards);if(mounted){setState(()=>canExit=true);WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)Navigator.pop(context);});}}}
 @override Widget build(BuildContext c)=>PopScope(canPop:canExit,onPopInvokedWithResult:(didPop,_) {if(!didPop)goBack();},child:Scaffold(resizeToAvoidBottomInset:true,appBar:focus?null:AppBar(backgroundColor:bg,leading:IconButton(onPressed:goBack,icon:const Icon(Icons.arrow_back_ios_new,size:20)),title:Text(widget.capsule?'时间胶囊':'写日记'),centerTitle:true,actions:[IconButton(onPressed:()=>setState(()=>focus=true),icon:const Icon(Icons.fullscreen)),IconButton(onPressed:text.text.trim().isNotEmpty&&mood!=null?finish:null,icon:const Icon(Icons.check))]),
 body:SafeArea(child:Column(children:[if(focus)Align(alignment:Alignment.centerRight,child:IconButton(onPressed:()=>setState(()=>focus=false),icon:const Icon(Icons.fullscreen_exit))),
 if(!focus)Padding(padding:const EdgeInsets.fromLTRB(24,8,24,8),child:Column(children:[Row(children:[Text(date(created),style:const TextStyle(color:muted)),const SizedBox(width:12),GestureDetector(onTap:()=>setState(()=>showMoods=!showMoods),child:CircleAvatar(radius:10,backgroundColor:mood==null?const Color(0xffd5d9df):moodColors[mood!]))]),
 if(showMoods)MoodDots(selected:mood,onChanged:(v){setState((){mood=v;showMoods=false;});saveDraft();})])),
 Expanded(child:Stack(children:[Padding(padding:const EdgeInsets.fromLTRB(24,16,24,32),child:TextField(controller:text,expands:true,maxLines:null,minLines:null,textAlignVertical:TextAlignVertical.top,decoration:const InputDecoration(border:InputBorder.none),style:const TextStyle(fontSize:18,height:1.7))),
 if(!focus)Positioned(right:24,bottom:8,child:Text('${text.text.characters.length} 字',style:const TextStyle(color:Color(0x66899bb7),fontSize:13)))])),
 if(!focus && photos.isNotEmpty)SizedBox(height:74,child:ListView.builder(scrollDirection:Axis.horizontal,itemCount:photos.length,itemBuilder:(c,i)=>Stack(children:[Padding(padding:const EdgeInsets.all(4),child:SizedBox(width:65,height:65,child:storedImage(photos[i]))),Positioned(right:0,top:0,child:InkWell(onTap:(){setState(()=>photos.removeAt(i));saveDraft();},child:const CircleAvatar(radius:10,child:Icon(Icons.close,size:14))))]))),
 if(!focus && audio!=null)Row(children:[AudioControl(file:audio!),IconButton(onPressed:(){setState(()=>audio=null);saveDraft();},icon:const Icon(Icons.close,size:18))]),
 if(!focus)Container(decoration:const BoxDecoration(border:Border(top:BorderSide(color:Color(0xffebe9e5)))),child:Row(children:[IconButton(onPressed:addPhotos,icon:const Icon(Icons.image_outlined)),IconButton(onPressed:recordAudio,icon:Icon(recording?Icons.stop_circle_outlined:Icons.mic_none)),if(recording)const Text('录音中 · 最长 10 秒',style:TextStyle(color:muted,fontSize:12))]))]))));
}
class Preview extends StatelessWidget {final String text;final int mood;final DateTime created;final DateTime? unlock;final List<String> photos;final String? audio;const Preview({super.key,required this.text,required this.mood,required this.created,this.unlock,this.photos=const [],this.audio});
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('预览'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('修改'))]),body:Padding(padding:const EdgeInsets.all(24),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Text(date(created),style:const TextStyle(color:muted)),const SizedBox(width:12),CircleAvatar(radius:8,backgroundColor:moodColors[mood])]),const SizedBox(height:30),Expanded(child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(text,style:const TextStyle(fontSize:18,height:1.7)),const SizedBox(height:20),Wrap(spacing:8,runSpacing:8,children:photos.map((p)=>SizedBox(width:100,height:100,child:storedImage(p))).toList()),if(audio!=null)AudioControl(file:audio!)]))),SizedBox(width:double.infinity,child:TextButton(onPressed:() async {final yes=await showDialog<bool>(context:c,builder:(c)=>AlertDialog(content:Text(unlock==null?'完成后不可删除哦，还要检查一下吗？':'这是给 ${date(unlock!)} 后的你的信，检查好后就寄出去喽'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(unlock==null?'再想想':'我还有想说的话')),TextButton(onPressed:()=>Navigator.pop(c,true),child:Text(unlock==null?'完成':'寄出去'))]));if(yes==true&&c.mounted)Navigator.pop(c,true);},child:Text(unlock==null?'完成':'寄出去')))])));
}
class Heart extends StatefulWidget {final ShikeStore store;const Heart({super.key,required this.store});@override State<Heart> createState()=>_HeartState();}
class _HeartState extends State<Heart> {bool heat=false;bool month=false;DateTime shown=DateTime.now();DateTime? selected;
 void showDay(DateTime d){setState(()=>selected=d);final list=widget.store.completed.where((e)=>sameDay(e.created,d)).toList();showModalBottomSheet(context:context,showDragHandle:true,backgroundColor:bg,builder:(c)=>SafeArea(child:Padding(padding:const EdgeInsets.all(20),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${day(d)} · ${list.length} 篇',style:const TextStyle(fontSize:18)),...list.map((e)=>ListTile(contentPadding:EdgeInsets.zero,title:Text(e.text,maxLines:1,overflow:TextOverflow.ellipsis),trailing:const Icon(Icons.chevron_right),onTap:(){Navigator.pop(c);openDiary(context,e);}))]))));}
 @override Widget build(BuildContext c){final records=widget.store.completed;final now=DateTime.now();final today=DateTime(now.year,now.month,now.day);final start=month?DateTime(now.year,now.month,1):today.subtract(Duration(days:today.weekday-1));final count=month?DateTime(now.year,now.month+1,0).day:7;final spots=<FlSpot>[];for(var i=0;i<count;i++){final d=start.add(Duration(days:i));final vals=records.where((e)=>sameDay(e.created,d)&&e.mood!=null).map((e)=>e.mood!).toList();if(vals.isNotEmpty)spots.add(FlSpot(i.toDouble(),vals.reduce((a,b)=>a+b)/vals.length));}
 return Padding(padding:const EdgeInsets.fromLTRB(24,18,24,0),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Heading('心迹'),const SizedBox(height:18),Row(children:[TextButton(onPressed:()=>setState(()=>heat=false),child:Text('趋势',style:TextStyle(color:heat?muted:ink))),TextButton(onPressed:()=>setState(()=>heat=true),child:Text('热力图',style:TextStyle(color:heat?ink:muted)))]),const Divider(),
 if(!heat)...[Center(child:SegmentedButton<bool>(segments:const [ButtonSegment(value:false,label:Text('周')),ButtonSegment(value:true,label:Text('月'))],selected:{month},onSelectionChanged:(v)=>setState(()=>month=v.first))),const SizedBox(height:26),const Text('每日平均心情'),const SizedBox(height:30),SizedBox(height:220,child:spots.isEmpty?const Center(child:Text('还没有心情记录',style:TextStyle(color:muted))):LineChart(LineChartData(minY:0,maxY:5,minX:0,maxX:(count-1).toDouble(),titlesData:const FlTitlesData(topTitles:AxisTitles(),rightTitles:AxisTitles()),lineTouchData:LineTouchData(touchCallback:(event,response){if(event is FlTapUpEvent && response?.lineBarSpots?.isNotEmpty==true){final x=response!.lineBarSpots!.first.x.toInt();showDay(start.add(Duration(days:x)));}}),lineBarsData:[LineChartBarData(spots:spots,color:const Color(0xffed8f75),barWidth:2,dotData:const FlDotData(show:true))]))) ]
 else ...[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[IconButton(onPressed:()=>setState(()=>shown=DateTime(shown.year,shown.month-1)),icon:const Icon(Icons.chevron_left)),Text('${shown.year}年${shown.month}月'),IconButton(onPressed:()=>setState(()=>shown=DateTime(shown.year,shown.month+1)),icon:const Icon(Icons.chevron_right))]),const SizedBox(height:15),const Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[Text('一'),Text('二'),Text('三'),Text('四'),Text('五'),Text('六'),Text('日')]),const SizedBox(height:15),Expanded(child:GridView.builder(gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7),itemCount:DateTime(shown.year,shown.month+1,0).day+DateTime(shown.year,shown.month,1).weekday-1,itemBuilder:(c,i){final offset=DateTime(shown.year,shown.month,1).weekday-1;final n=i-offset+1;if(n<1)return const SizedBox();final d=DateTime(shown.year,shown.month,n);final es=records.where((e)=>sameDay(e.created,d)).toList()..sort((a,b)=>b.created.compareTo(a.created));final isSelected=selected!=null&&sameDay(selected!,d);return InkWell(onTap:()=>showDay(d),child:Center(child:Container(width:38,height:38,alignment:Alignment.center,decoration:BoxDecoration(shape:BoxShape.circle,color:es.isEmpty?Colors.transparent:moodColors[es.first.mood??0],border:isSelected?Border.all(color:Colors.white,width:4):null,boxShadow:isSelected?[const BoxShadow(color:Color(0x26000000),blurRadius:5,offset:Offset(0,2))]:null),child:Text('$n',style:const TextStyle(color:ink,fontSize:13)))));}))]]));}
}
class Corner extends StatelessWidget {final ShikeStore store;const Corner({super.key,required this.store});
 @override Widget build(BuildContext c)=>Padding(padding:const EdgeInsets.fromLTRB(24,18,24,0),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Heading('角落'),const SizedBox(height:30),const Text('拾刻',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const Text('把此刻轻轻拾起',style:TextStyle(color:muted)),const SizedBox(height:35),...[(Icons.image_outlined,'拾影'),(Icons.credit_card_outlined,'卡包'),(Icons.cloud_outlined,'备份与迁移'),(Icons.shield_outlined,'显示与权限'),(Icons.info_outline,'关于拾刻')].map((item)=>Column(children:[ListTile(contentPadding:EdgeInsets.zero,leading:Icon(item.$1),title:Text(item.$2),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>item.$2=='拾影'?const Gallery():item.$2=='卡包'?const CardPack():item.$2=='备份与迁移'?BackupPage(store:store):PlaceholderPage(title:item.$2)))),const Divider(height:1,color:Color(0xffe9e8e5))]))]));}
class PlaceholderPage extends StatelessWidget {final String title;const PlaceholderPage({super.key,required this.title});
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:Text(title)),body:Center(child:Text(title=='关于拾刻'?'拾刻\n把此刻轻轻拾起\n\n写下的都算数，完成的都留下。':'此功能尚未接入',textAlign:TextAlign.center,style:const TextStyle(color:muted,height:2))));}
