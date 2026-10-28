import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shike/refined/controller.dart';
import 'package:shike/refined/design.dart';
import 'package:shike/refined/heart.dart';
import 'package:shike/refined/keep_feedback.dart';
import 'package:shike/refined/radial_filter.dart';
import 'package:shike/refined/shell.dart';

void dimensions(
  WidgetTester tester, {
  double width = 390,
  double height = 844,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('周横轴显示周一到周日，月横轴仅显示指定日期和月末', () {
    final monday = DateTime(2026, 10, 26);
    expect(
      List.generate(
        7,
        (i) => trendAxisLabel(
          DateTime(monday.year, monday.month, monday.day + i),
          monthly: false,
          totalDays: 7,
        ),
      ),
      ['一', '二', '三', '四', '五', '六', '日'],
    );
    for (final count in [28, 29, 30, 31]) {
      final labels = List.generate(
        count,
        (i) => trendAxisLabel(
          DateTime(2026, 1, i + 1),
          monthly: true,
          totalDays: count,
        ),
      ).whereType<String>().toList();
      expect(labels.last, '月末');
      expect(labels, containsAll(['1日', '7日', '14日', '21日']));
      if (count > 28) expect(labels, contains('28日'));
      expect(labels.length, lessThanOrEqualTo(6));
    }
  });
  testWidgets('收好成功后文字飞入拾光，清空输入不显示居中文案，无震动', (tester) async {
    dimensions(tester);
    var haptics = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') haptics++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = RefinedController(PreviewStore(), demo: true);
    await tester.pumpWidget(RefinedApp(controller: controller));
    await tester.enterText(
      find.byKey(const ValueKey('quick-text')),
      '这句话被轻轻收好。',
    );
    await tester.tap(find.bySemanticsLabel('心情 3 分'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('quick-submit')));
    await tester.pump();
    expect(controller.store.completed.length, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('quick-text')))
          .controller!
          .text,
      isEmpty,
    );
    expect(tester.widget<MoodChoices>(find.byType(MoodChoices)).value, isNull);
    expect(find.byType(KeptFlight), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('kept-light-point')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('收好啦'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1001));
    await tester.pump();
    expect(find.text('收好啦'), findsNothing);
    expect(haptics, 0);
  });
  testWidgets('环形心情筛选可多选、独立取消、恢复全部，并从右上方开始', (tester) async {
    dimensions(tester);
    Set<int> selected = {0, 1, 2, 3, 4, 5};
    await tester.pumpWidget(
      MaterialApp(
        theme: Paper.theme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, setState) => Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 100, right: 24),
                child: MoodRadialFilter(
                  selected: selected,
                  onChanged: (v) => setState(() => selected = v),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('心情筛选'));
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.bySemanticsLabel('收起心情筛选'));
    final zero = tester.getCenter(find.bySemanticsLabel('筛选心情 0 分'));
    expect(zero.dx, greaterThan(center.dx));
    expect(zero.dy, lessThan(center.dy));
    await tester.tap(find.bySemanticsLabel('筛选心情 0 分'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('筛选心情 1 分'));
    await tester.pumpAndSettle();
    expect(selected, {2, 3, 4, 5});
    await tester.tap(find.bySemanticsLabel('筛选心情 0 分'));
    await tester.pumpAndSettle();
    expect(selected, {0, 2, 3, 4, 5});
    await tester.tap(find.text('恢复全部'));
    await tester.pumpAndSettle();
    expect(selected, {0, 1, 2, 3, 4, 5});
    await tester.tap(find.bySemanticsLabel('收起心情筛选'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('筛选心情 0 分'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('320宽度的环形筛选不超出屏幕，点击空白可收起', (tester) async {
    dimensions(tester, width: 320, height: 568);
    await tester.pumpWidget(
      MaterialApp(
        theme: Paper.theme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: MoodRadialFilter(
              selected: const {0, 1, 2, 3, 4, 5},
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('心情筛选'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      final rect = tester.getRect(find.bySemanticsLabel('筛选心情 $i 分'));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.width, 44);
    }
    await tester.tapAt(const Offset(10, 500));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('筛选心情 0 分'), findsNothing);
  });
}
