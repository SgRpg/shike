import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shike/src/store.dart';
import 'package:shike/src/app.dart';
import 'package:shike/src/rewards.dart';
import 'package:shike/src/backup.dart';
import 'dart:convert';
import 'dart:typed_data';

Diary entry(String id, String state, {DateTime? unlock}) => Diary(id:id,text:'日记',mood:2,created:DateTime(2026,10,1),updated:DateTime(2026,10,1),state:state,unlockAt:unlock);
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUp(()=>SharedPreferences.setMockInitialValues({}));
 test('草稿可更新并完成，完成后不可修改或删除',() async {
   final s=await ShikeStore.openPreferences();await s.save(entry('1','draft'));await s.save(entry('1','done'));
   expect(s.completed.length,1);expect(()=>s.save(entry('1','draft')),throwsStateError);
   await s.deleteDraft('1');expect(s.completed.length,1);
   final restored=await ShikeStore.openPreferences();expect(restored.completed.single.text,'日记');
 });
 test('未解锁胶囊不可进入已完成集合，到期后可见',() async {
   final s=await ShikeStore.openPreferences();await s.save(entry('locked','capsule',unlock:DateTime.now().add(const Duration(days:1))));
   await s.save(entry('open','capsule',unlock:DateTime.now().subtract(const Duration(days:1))));
   expect(s.completed.map((e)=>e.id),['open']);
 });
 test('累计写满 10 天获得点歌卡，重复判断不会重复获得',() async {
   final s=await ShikeStore.openPreferences();
   for(var i=1;i<=10;i++){final d=DateTime(2026,1,i);await s.save(Diary(id:'$i',text:'日记',mood:3,created:d,updated:d,state:'done'));}
   await Rewards.evaluate(s,s.completed.first);await Rewards.evaluate(s,s.completed.first);
   final cards=await Rewards.load();expect(cards.where((x)=>x.key=='total-10').length,1);
 });
 test('备份恢复保留既有日记，相同内容不会重复导入',() async {
   final s=await ShikeStore.openPreferences();await s.save(entry('1','done'));final backup=await BackupService.export(s);
   expect(await BackupService.restore(s,backup),0);expect(s.completed.length,1);
   final json=Map<String,dynamic>.from(jsonDecode(utf8.decode(backup)));json['entries'][0]['text']='不同的内容';
   final other=Uint8List.fromList(utf8.encode(jsonEncode(json)));expect(await BackupService.restore(s,other),1);
   expect(s.completed.map((e)=>e.text).toSet(),{'日记','不同的内容'});
 });
 test('损坏的备份在导入前被拒绝',() async {
   final s=await ShikeStore.openPreferences();await s.save(entry('1','done'));
   expect(()=>BackupService.validate(Uint8List.fromList(utf8.encode('{'))),throwsFormatException);
   expect(s.completed.length,1);
 });
 testWidgets('一句话需要文字和心情才可以收好', (tester) async {
   final s=await ShikeStore.openPreferences();await tester.pumpWidget(ShikeApp(store:s));
   expect(find.text('收好'),findsOneWidget);await tester.enterText(find.byType(EditableText).first,'今天');await tester.pump();
   expect(s.completed,isEmpty);
   await tester.tap(find.bySemanticsLabel('心情 3 分'));await tester.pump();await tester.tap(find.text('收好'));await tester.pumpAndSettle();
   expect(s.completed.single.mood,3);expect(s.completed.single.text,'今天');
 });
 testWidgets('写日记返回时保留草稿，重新打开后可完成', (tester) async {
   final s=await ShikeStore.openPreferences();await tester.pumpWidget(ShikeApp(store:s));
   await tester.tap(find.text('写日记'));await tester.pumpAndSettle();
   await tester.enterText(find.byType(EditableText).last,'一段新的记录');await tester.pump();
   await tester.tap(find.byIcon(Icons.arrow_back_ios_new));await tester.pumpAndSettle();
   expect(s.drafts.single.text,'一段新的记录');
   await tester.tap(find.text('写日记'));await tester.pumpAndSettle();
   await tester.tap(find.text('一段新的记录'));await tester.pumpAndSettle();
   expect(find.text('一段新的记录'),findsOneWidget);
 });
}
