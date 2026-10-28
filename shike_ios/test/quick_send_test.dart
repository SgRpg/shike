import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shike/refined/design.dart';
import 'package:shike/refined/controller.dart';
import 'package:shike/refined/quick_send.dart';
import 'package:shike/refined/keep_feedback.dart';
import 'package:shike/refined/shell.dart';

void main() {
  testWidgets('首页没有心情标题和收好文字，输入箭头成功保存后隐藏并保留动效', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = RefinedController(PreviewStore(), demo: true);
    await tester.pumpWidget(RefinedApp(controller: controller));
    expect(find.text('心情'), findsNothing);
    expect(find.text('收好'), findsNothing);
    expect(find.byType(QuickSendArrow), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('quick-text')),
      '把小小的此刻收好。',
    );
    await tester.pump();
    expect(find.byType(QuickSendArrow), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.byKey(const ValueKey('quick-submit')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.bySemanticsLabel('心情 3 分'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-submit')));
    await tester.pump();
    expect(controller.store.completed.length, 1);
    expect(find.byType(QuickSendArrow), findsNothing);
    expect(find.byType(KeptFlight), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('空白时隐藏，有文字时出现，未选心情可点提醒，清空后隐藏', (tester) async {
    final input = TextEditingController();
    addTearDown(input.dispose);
    var ready = false;
    var saves = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        theme: Paper.theme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, setState) {
              update = setState;
              return TextField(
                controller: input,
                onChanged: (_) => setState(() {}),
                decoration: quickEntryDecoration(
                  hasText: input.text.trim().isNotEmpty,
                  busy: false,
                  onSend: ready ? () => saves++ : null,
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(find.byType(QuickSendArrow), findsNothing);
    await tester.enterText(find.byType(TextField), '风很轻。');
    await tester.pump();
    expect(find.byType(QuickSendArrow), findsOneWidget);
    final button = find.byKey(const ValueKey('quick-submit'));
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    expect(tester.getSize(button), const Size(44, 44));
    expect(
      tester.getSize(find.byKey(const ValueKey('quick-send-glyph'))),
      const Size(14, 14),
    );
    expect(
      tester.getRect(find.byType(TextField)).contains(tester.getCenter(button)),
      isTrue,
    );
    update(() => ready = true);
    await tester.pump();
    await tester.tap(button);
    expect(saves, 1);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(find.byType(QuickSendArrow), findsNothing);
  });

  testWidgets('320宽度两行正文不会与发送箭头重叠或溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: Paper.theme(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: TextField(
              maxLines: 2,
              minLines: 1,
              controller: TextEditingController(
                text: '今天留下一段很长很长的文字，慢慢写也没有关系。',
              ),
              decoration: quickEntryDecoration(
                hasText: true,
                busy: false,
                onSend: () {},
              ),
            ),
          ),
        ),
      ),
    );
    final button = tester.getRect(find.byKey(const ValueKey('quick-submit')));
    final editable = tester.getRect(find.byType(EditableText));
    expect(editable.right, lessThanOrEqualTo(button.left));
    expect(button.right, lessThanOrEqualTo(296));
    expect(tester.takeException(), isNull);
  });
}
