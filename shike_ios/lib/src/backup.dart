import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'store.dart';

class BackupService {
 static const _prefix='data:image;base64,';
 static Future<String> _read(String file) async {
  if(file.startsWith(_prefix))return file.substring(_prefix.length);
  if(kIsWeb)throw const FormatException('无法读取该媒体文件');
  return base64Encode(await File(file).readAsBytes());
 }
 static Future<String> _write(String data,{required bool image}) async {
  final bytes=base64Decode(data);if(kIsWeb)return '$_prefix$data';
  final dir=Directory(p.join((await getApplicationDocumentsDirectory()).path,'restored'));
  await dir.create(recursive:true);final name='${DateTime.now().microsecondsSinceEpoch}-${UniqueKey().toString().replaceAll(RegExp('[^a-zA-Z0-9]'), '')}.${image?'img':'m4a'}';
  final file=File(p.join(dir.path,name));await file.writeAsBytes(bytes,flush:true);return file.path;
 }
 static Future<Map<String,dynamic>> encodeDiary(Diary d) async {
  final j=d.toJson();j['photos']=await Future.wait(d.photos.map(_read));j['audio']=d.audio==null?null:await _read(d.audio!);return j;
 }
 static Future<Uint8List> export(ShikeStore store) async {
  final prefs=await SharedPreferences.getInstance();final gallery=(jsonDecode(prefs.getString('gallery.items')??'[]') as List).map((x)=>Map<String,dynamic>.from(x)).toList();
  for(final item in gallery){item['data']=await _read(item['path'] as String);item.remove('path');}
  final payload={'format':'shike-backup','version':1,'entries':await Future.wait(store.entries.map(encodeDiary)),
   'gallery':gallery,'cards':jsonDecode(prefs.getString('rewards.cards')??'[]'),
   'randomWeek':prefs.getString('rewards.randomWeek'),'recentLow':prefs.getStringList('gentle.recent')??<String>[]};
  return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
 }
 static Future<Uri?> save(ShikeStore store) async {final data=await export(store);return FilePicker.saveFile(dialogTitle:'保存拾刻备份',fileName:'拾刻备份.json',mimeType:'application/json',bytes:data);}
 static Future<Uint8List?> choose() async {final f=await FilePicker.pickFile(type:FileType.custom,allowedExtensions:['json']);if(f==null)return null;return f.readAsBytes();}
 static Map<String,dynamic> validate(Uint8List bytes) {
  final root=Map<String,dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  if(root['format']!='shike-backup'||root['version']!=1||root['entries'] is! List||root['gallery'] is! List||root['cards'] is! List)throw const FormatException('不支持的备份格式');
  final ids=<String>{};for(final raw in root['entries'] as List){final j=Map<String,dynamic>.from(raw as Map);final entry=Diary.fromJson(j);if(!ids.add(entry.id)||!['draft','done','capsule'].contains(entry.state)||(entry.mood!=null&&(entry.mood!<0||entry.mood!>5))||(entry.state=='capsule'&&entry.unlockAt==null))throw const FormatException('日记内容无效');for(final photo in j['photos'] as List){base64Decode(photo as String);}if(j['audio']!=null)base64Decode(j['audio'] as String);}
  for(final raw in root['gallery'] as List){final j=Map<String,dynamic>.from(raw as Map);base64Decode(j['data'] as String);if(j['description'] is! String)throw const FormatException('照片描述无效');}
  for(final raw in root['cards'] as List){final j=Map<String,dynamic>.from(raw as Map);if(j['key'] is! String||j['title'] is! String||j['description'] is! String)throw const FormatException('卡片无效');}
  return root;
 }
 static Future<int> restore(ShikeStore store,Uint8List bytes) async {
  final root=validate(bytes);final prefs=await SharedPreferences.getInstance();var imported=0;
  final existing=<String,Map<String,dynamic>>{};for(final e in store.entries){existing[e.id]=await encodeDiary(e);}
  for(final raw in root['entries'] as List){final j=Map<String,dynamic>.from(raw as Map);final original=j['id'] as String;
   if(existing.containsKey(original)){if(jsonEncode(existing[original])==jsonEncode(j))continue;j['id']=store.newId();}
   j['photos']=await Future.wait((j['photos'] as List).map((x)=>_write(x as String,image:true)));if(j['audio']!=null)j['audio']=await _write(j['audio'] as String,image:false);
   await store.save(Diary.fromJson(j));imported++;
  }
  final gallery=(jsonDecode(prefs.getString('gallery.items')??'[]') as List).map((x)=>Map<String,dynamic>.from(x)).toList();
  final currentGallery=<String>{};for(final g in gallery){try{currentGallery.add('${await _read(g['path'] as String)}|${g['description']}');}catch(_){}}
  for(final raw in root['gallery'] as List){final g=Map<String,dynamic>.from(raw as Map);final key='${g['data']}|${g['description']}';if(!currentGallery.add(key))continue;gallery.add({'path':await _write(g['data'] as String,image:true),'description':g['description']});}
  await prefs.setString('gallery.items',jsonEncode(gallery));
  final cards=(jsonDecode(prefs.getString('rewards.cards')??'[]') as List).map((x)=>Map<String,dynamic>.from(x)).toList();final keys=cards.map((x)=>x['key']).toSet();for(final raw in root['cards'] as List){final card=Map<String,dynamic>.from(raw as Map);if(keys.add(card['key']))cards.add(card);}await prefs.setString('rewards.cards',jsonEncode(cards));
  if(prefs.getString('rewards.randomWeek')==null&&root['randomWeek'] is String)await prefs.setString('rewards.randomWeek',root['randomWeek'] as String);
  return imported;
 }
}
class BackupPage extends StatelessWidget {final ShikeStore store;const BackupPage({super.key,required this.store});
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('备份与迁移')),body:ListView(padding:const EdgeInsets.all(24),children:[const Text('把拾起的都带走。',style:TextStyle(color:Color(0xff899bb7))),const SizedBox(height:20),
 ListTile(title:const Text('导出备份包'),subtitle:Text('包含 ${store.entries.length} 篇日记和草稿'),trailing:const Icon(Icons.chevron_right),onTap:() async {try{final output=await BackupService.save(store);if(c.mounted&&output!=null)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('备份已导出')));}catch(_){if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('导出失败，请检查媒体文件及存储空间')));}}),
 ListTile(title:const Text('导入备份包'),trailing:const Icon(Icons.chevron_right),onTap:() async {try{final data=await BackupService.choose();if(data==null)return;final result=BackupService.validate(data);if(!c.mounted)return;final yes=await showDialog<bool>(context:c,builder:(c)=>AlertDialog(title:const Text('导入备份？'),content:Text('包含 ${(result['entries'] as List).length} 篇日记和草稿，将与现有内容合并。'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('取消')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('导入'))]));if(yes!=true)return;final n=await BackupService.restore(store,data);if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(SnackBar(content:Text('已导入 $n 篇日记或草稿')));}catch(_){if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('导入未完成，请检查备份文件；已有内容未被覆盖')));}}),
 const ListTile(title:Text('附近迁移'),subtitle:Text('尚未接入'))]));}
