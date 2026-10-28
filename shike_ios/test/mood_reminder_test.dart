import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shike/refined/design.dart';
import 'package:shike/refined/controller.dart';
import 'package:shike/refined/keep_feedback.dart';
import 'package:shike/refined/mood_reminder.dart';
import 'package:shike/refined/shell.dart';

void main() {
  testWidgets('首页缺少心情只微弹跳，文字保留，无云朵和文案，补选后正常保存', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = RefinedController(PreviewStore(), demo: true);
    await tester.pumpWidget(RefinedApp(controller: controller));
    await tester.enterText(find.byKey(const ValueKey('quick-text')), '先留下一句话。');
    await tester.pump();
    final send = find.byKey(const ValueKey('quick-submit'));
    await tester.tap(send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 112));
    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('mood-wave-dot-0')),
    );
    expect(transform.transform.getTranslation().y, closeTo(-5, .03));
    expect(controller.store.completed, isEmpty);
    expect(find.text('记得选个心情哦'), findsNothing);
    expect(find.text('收好啦'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('quick-text')))
          .controller!
          .text,
      '先留下一句话。',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('心情 3 分'));
    await tester.pump();
    await tester.tap(send);
    await tester.pump();
    expect(controller.store.completed.length, 1);
    expect(find.byType(KeptFlight), findsOneWidget);
    expect(find.byType(QuickSendHalo), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('记得选个心情哦'), findsNothing);
    expect(find.text('收好啦'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('缺少心情只调用提示回调，有心情直接发送，忙时禁用', (tester) async {
    var busy = false;
    var ready = false;
    var saves = 0;
    var nudges = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: Paper.theme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, setState) {
              update = setState;
              return Center(
                child: quickSendControl(
                  c,
                  busy: busy,
                  onSend: ready ? () => saves++ : null,
                  onMissingMood: () => nudges++,
                  arrow: const SizedBox.square(dimension: 14),
                ),
              );
            },
          ),
        ),
      ),
    );
    final send = find.byKey(const ValueKey('quick-submit'));
    await tester.tap(send);
    expect(saves, 0);
    expect(nudges, 1);
    update(() => ready = true);
    await tester.pump();
    await tester.tap(send);
    expect(saves, 1);
    expect(nudges, 1);
    update(() => busy = true);
    await tester.pump();
    expect(tester.widget<TextButton>(send).onPressed, isNull);
  });

  testWidgets('保留30px半透明圆底', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: QuickSendHalo(child: const SizedBox.square(dimension: 14)),
          ),
        ),
      ),
    );
    final halo = find.byKey(const ValueKey('quick-send-halo'));
    expect(tester.getSize(halo), const Size(30, 30));
    final box = tester.widget<DecoratedBox>(
      find.descendant(of: halo, matching: find.byType(DecoratedBox)),
    );
    final decoration = box.decoration as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color!.a, closeTo(.1, .01));
  });
}
