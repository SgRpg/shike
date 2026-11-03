import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shike/src/store.dart';
import 'package:shike/refined/controller.dart';
import 'package:shike/refined/design.dart';
import 'package:shike/refined/shell.dart';
import 'package:shike/refined/editor.dart';
import 'package:shike/refined/gallery.dart';
import 'package:shike/refined/cards.dart';
import 'package:shike/refined/fixtures.dart';
import 'package:shike/refined/backup_page.dart';
import 'package:shike/refined/export.dart';

import 'dart:ui' as ui;
import 'dart:convert';

class DelayedStore extends PreviewStore {
  Completer<void>? gate;
  bool fail = false;
  int commits = 0;
  @override
  Future<void> save(Diary value) async {
    if (value.state == 'done') {
      commits++;
      if (gate != null) await gate!.future;
      if (fail) throw StateError('test save failure');
    }
    return super.save(value);
  }
}

Diary diary(String id, DateTime date, int mood) => Diary(
  id: id,
  text: '测试记录 $id',
  mood: mood,
  created: date,
  updated: date,
  state: 'done',
);

void phone(WidgetTester tester, {double width = 390, double height = 844}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('同一天多篇：曲线均值与热力图最后一篇保持不同规则', () {
    final d = DateTime(2026, 10, 27);
    final group = MoodDay(d, [
      diary('early', DateTime(2026, 10, 27, 8), 0),
      diary('late', DateTime(2026, 10, 27, 20), 4),
    ]);
    expect(group.mean, 2);
    expect(group.lastMood, 4);
  });
  test('合并备份时，冲突日记的引用和元信息跟随新ID', () async {
    final incoming = RefinedController(PreviewStore());
    await incoming.initialize();
    final date = DateTime(2026, 10, 27);
    await incoming.store.save(diary('same-id', date, 3));
    await incoming.store.save(
      Diary(
        id: 'source',
        text: '引用这段',
        mood: 4,
        created: date,
        updated: date,
        state: 'done',
      ),
    );
    await incoming.saveLinks('source', [
      const JournalReference(target: 'same-id', text: '引用', start: 0, end: 2),
    ]);
    await incoming.snapshot('same-id', '2026.10.27 · 成都');
    final data = await RefinedBackupCodec.encode(incoming);
    // A fresh receiving controller has an existing, different journal with that ID.
    SharedPreferences.setMockInitialValues({});
    final target = RefinedController(PreviewStore());
    await target.initialize();
    await target.store.save(
      Diary(
        id: 'same-id',
        text: '原设备的内容',
        mood: 2,
        created: date,
        updated: date,
        state: 'done',
      ),
    );
    expect(await RefinedBackupCodec.restore(target, data), 2);
    final imported = target.store.entries.firstWhere(
      (e) => e.id != 'same-id' && e.id != 'source',
    );
    expect(target.references['source']!.single.target, imported.id);
    expect(target.savedMetadata(imported), '2026.10.27 · 成都');
    expect(
      target.store.entries.firstWhere((e) => e.id == 'same-id').text,
      '原设备的内容',
    );
  });
  testWidgets('日记PNG导出包含照片页，取消保存不报告成功', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(4, 4);
      picture.dispose();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final date = DateTime(2026, 10, 27);
      final entry = Diary(
        id: 'export',
        text: '文字与照片',
        mood: 3,
        created: date,
        updated: date,
        state: 'done',
        photos: [
          'data:image;base64,${base64Encode(bytes!.buffer.asUint8List())}',
        ],
      );
      var calls = 0;
      final pages = await exportDiary(
        entry,
        includeMood: true,
        saver: (bytes, name) async {
          calls++;
          expect(bytes.take(4).toList(), [137, 80, 78, 71]);
          return true;
        },
      );
      expect(pages, 2);
      expect(calls, 2);
      expect(
        await exportDiary(
          entry,
          includeMood: false,
          saver: (_, _) async => false,
        ),
        0,
      );
    });
  });
  testWidgets('收好等待时防连点，成功只产生一篇正式日记', (tester) async {
    phone(tester);
    final store = DelayedStore()..gate = Completer<void>();
    final controller = RefinedController(store, demo: true);
    await tester.pumpWidget(RefinedApp(controller: controller));
    await tester.enterText(find.byKey(const ValueKey('quick-text')), '轻轻留下一句。');
    await tester.tap(find.bySemanticsLabel('心情 3 分'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-submit')));
    await tester.pump();
    final button = tester.widget<TextButton>(
      find.byKey(const ValueKey('quick-submit')),
    );
    expect(button.onPressed, isNull);
    expect(store.commits, 1);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(store.completed.length, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('quick-text')))
          .controller!
          .text,
      isEmpty,
    );
  });
  testWidgets('保存失败保留文字和心情，允许重新提交', (tester) async {
    phone(tester);
    final store = DelayedStore()..fail = true;
    final controller = RefinedController(store, demo: true);
    await tester.pumpWidget(RefinedApp(controller: controller));
    await tester.enterText(find.byKey(const ValueKey('quick-text')), '不丢失的内容');
    await tester.tap(find.bySemanticsLabel('心情 3 分'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-submit')));
    await tester.pumpAndSettle();
    expect(store.completed, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('quick-text')))
          .controller!
          .text,
      '不丢失的内容',
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('quick-submit')))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('编辑器空白、触控范围与键盘前后工具排列', (tester) async {
    phone(tester);
    final controller = RefinedController(PreviewStore(), demo: true);
    await tester.pumpWidget(RefinedApp(controller: controller));
    await tester.tap(find.text('写日记'));
    await tester.pumpAndSettle();
    expect(find.byType(RefinedEditor), findsOneWidget);
    expect(find.text('想写什么，就写什么'), findsNothing);
    final mood = find.bySemanticsLabel(RegExp('选择心情'));
    expect(tester.getSize(mood).width, greaterThanOrEqualTo(44));
    final image = find.byWidgetPredicate(
      (w) => w is IconAction && w.label == '添加图片',
    );
    final mic = find.byWidgetPredicate(
      (w) => w is IconAction && w.label == '录制语音',
    );
    final closedGap = tester.getCenter(mic).dx - tester.getCenter(image).dx;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    final openGap = tester.getCenter(mic).dx - tester.getCenter(image).dx;
    expect(closedGap, greaterThan(openGap));
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
  });
  testWidgets('当日弹层空状态仍为全宽，只有拖动条，无关闭X', (tester) async {
    phone(tester);
    final controller = RefinedController(PreviewStore(), demo: true);
    await tester.pumpWidget(RefinedApp(controller: controller));
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('热力图'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel(RegExp('月1日，0篇日记')));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(BottomSheet)).width, 390);
    expect(find.text('这一天还没有记录。'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is IconAction && w.mark == Mark.close),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('320宽大字号角落可以滚动，没有布局溢出', (tester) async {
    phone(tester, width: 320, height: 568);
    final controller = RefinedController(PreviewStore(), demo: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: Paper.theme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.8),
          ),
          child: Scaffold(body: CornerPage(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('关于拾刻'), 200);
    expect(find.text('关于拾刻'), findsOneWidget);
  });
  testWidgets('拾影能切换照片，卡片详情具有保存入口', (tester) async {
    phone(tester);
    final controller = visualFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: Paper.theme(),
        home: RefinedGallery(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('傍晚的云').first);
    await tester.pumpAndSettle();
    expect(find.text('这一张'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.text('一杯热茶'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: Paper.theme(),
        home: RefinedCardDetail(
          controller: controller,
          card: controller.cards.first,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('存到相册'), findsOneWidget);
    expect(find.byType(CardPoster), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
