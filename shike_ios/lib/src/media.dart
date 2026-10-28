import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

Future<String> copyImage(XFile file) async {
 if(kIsWeb)return 'data:image;base64,${base64Encode(await file.readAsBytes())}';
 final dir=Directory(p.join((await getApplicationDocumentsDirectory()).path,'images'));
 await dir.create(recursive:true);final ext=p.extension(file.name);
 final target=p.join(dir.path,'${const Uuid().v4()}$ext');
 await File(file.path).copy(target);return target;
}
Widget storedImage(String path,{BoxFit fit=BoxFit.cover}) {
 if(path.startsWith('data:image;base64,'))return Image.memory(base64Decode(path.substring('data:image;base64,'.length)),fit:fit);
 if(kIsWeb)return const SizedBox.shrink();
 return Image.file(File(path),fit:fit,errorBuilder:(_,_,_)=>const Icon(Icons.broken_image_outlined));
}
class Gallery extends StatefulWidget {const Gallery({super.key});@override State<Gallery> createState()=>_GalleryState();}
class _GalleryState extends State<Gallery> {
 List<Map<String,dynamic>> items=[];
 @override void initState(){super.initState();load();}
 Future<void> load() async {final p=await SharedPreferences.getInstance();final raw=p.getString('gallery.items');if(raw!=null){items=(jsonDecode(raw) as List).map((e)=>Map<String,dynamic>.from(e)).toList();if(mounted)setState((){});}}
 Future<void> persist() async {final p=await SharedPreferences.getInstance();await p.setString('gallery.items',jsonEncode(items));if(mounted)setState((){});}
 Future<void> add() async {try {final files=await ImagePicker().pickMultiImage();for(final file in files){items.insert(0,{'path':await copyImage(file),'description':''});}await persist();}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('无法导入照片，请检查相册权限。')));}}
 Future<void> detail(int index) async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>GalleryDetail(item:items[index],onEdit:(v) async {items[index]['description']=v;await persist();},onDelete:() async {items.removeAt(index);await persist();})));}
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('拾影'),centerTitle:true,actions:[IconButton(onPressed:add,icon:const Icon(Icons.add))]),body:items.isEmpty?const Center(child:Text('还没有照片。存一张想留住的吧。',style:TextStyle(color:Color(0xff899bb7)))):GridView.builder(padding:const EdgeInsets.all(8),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:3,mainAxisSpacing:6,crossAxisSpacing:6,childAspectRatio:.72),itemCount:items.length,itemBuilder:(c,i){final x=items[i];return ClipRRect(borderRadius:BorderRadius.circular(5),child:InkWell(onTap:()=>detail(i),child:Stack(fit:StackFit.expand,children:[storedImage(x['path'] as String),if((x['description'] as String).isNotEmpty)Align(alignment:Alignment.bottomCenter,child:Container(width:double.infinity,padding:const EdgeInsets.fromLTRB(6,14,6,5),decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.transparent,Colors.black54])),child:Text(x['description'] as String,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:11))))])));}));
}
class GalleryDetail extends StatefulWidget {final Map<String,dynamic> item;final Future<void> Function(String) onEdit;final Future<void> Function() onDelete;const GalleryDetail({super.key,required this.item,required this.onEdit,required this.onDelete});@override State<GalleryDetail> createState()=>_GalleryDetailState();}
class _GalleryDetailState extends State<GalleryDetail> {
 @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('拾影'),centerTitle:true),body:ListView(padding:const EdgeInsets.all(24),children:[AspectRatio(aspectRatio:.82,child:ClipRRect(borderRadius:BorderRadius.circular(8),child:storedImage(widget.item['path'] as String))),const SizedBox(height:24),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('这一张'),TextButton(onPressed:() async {final input=TextEditingController(text:widget.item['description'] as String);final v=await showDialog<String>(context:c,builder:(c)=>AlertDialog(title:const Text('照片描述'),content:TextField(controller:input,maxLines:2),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('取消')),TextButton(onPressed:()=>Navigator.pop(c,input.text.trim()),child:const Text('保存'))]));if(v!=null){await widget.onEdit(v);if(mounted)setState((){});}},child:const Text('编辑'))]),Text(widget.item['description'] as String),const SizedBox(height:25),const Divider(),TextButton(onPressed:() async {final yes=await showDialog<bool>(context:c,builder:(c)=>AlertDialog(title:const Text('删除这张照片？'),content:const Text('删除后不可恢复。'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('取消')),TextButton(onPressed:()=>Navigator.pop(c,true),child:const Text('删除'))]));if(yes==true){await widget.onDelete();if(c.mounted)Navigator.pop(c);}},child:const Text('删除照片',style:TextStyle(color:Colors.redAccent)))]));
}
