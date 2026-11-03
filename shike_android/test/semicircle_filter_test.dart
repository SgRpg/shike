import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shike/refined/design.dart';
import 'package:shike/refined/controller.dart';
import 'package:shike/refined/heart.dart';
import 'package:shike/refined/semicircle_filter.dart';
import 'package:shike/src/store.dart';

void main() {
  testWidgets('热力图联动：全部到4，到3和4，到仅3，最后恢复全部', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = PreviewStore();
    final now = DateTime.now();
    for (final pair in [(10, 4), (11, 3), (12, 1)]) {
      final date = DateTime(now.year, now.month, pair.$1);
      store.entries.add(
        Diary(
          id: 'calendar-${pair.$1}',
          text: '测试',
          mood: pair.$2,
          created: date,
          updated: date,
          state: 'done',
        ),
      );
    }
    final controller = RefinedController(store, demo: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: Paper.theme(),
        home: Scaffold(body: HeartPage(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('热力图'));
    await tester.pumpAndSettle();
    Color? dayColor(int day) {
      final daySemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics && w.properties.label == '${now.month}月$day日，1篇日记',
      );
      final circles = tester.widgetList<Container>(
        find.descendant(of: daySemantics, matching: find.byType(Container)),
      );
      final circle = circles.singleWhere((w) => w.constraints?.maxWidth == 38);
      return (circle.decoration as BoxDecoration).color;
    }

    expect(dayColor(10), Paper.mood[4]);
    expect(dayColor(11), Paper.mood[3]);
    expect(dayColor(12), Paper.mood[1]);
    await tester.tap(find.bySemanticsLabel('心情筛选'));
    await tester.pumpAndSettle();
    expect(find.text('恢复全部'), findsNothing);
    await tester.tap(find.bySemanticsLabel('筛选心情 4 分'));
    await tester.pumpAndSettle();
    expect(dayColor(10), Paper.mood[4]);
    expect(dayColor(11), Colors.transparent);
    expect(dayColor(12), Colors.transparent);
    await tester.tap(find.bySemanticsLabel('筛选心情 3 分'));
    await tester.pumpAndSettle();
    expect(dayColor(10), Paper.mood[4]);
    expect(dayColor(11), Paper.mood[3]);
    await tester.tap(find.bySemanticsLabel('筛选心情 4 分'));
    await tester.pumpAndSettle();
    expect(dayColor(10), Colors.transparent);
    expect(dayColor(11), Paper.mood[3]);
    await tester.tap(find.bySemanticsLabel('筛选心情 3 分'));
    await tester.pumpAndSettle();
    expect(dayColor(10), Paper.mood[4]);
    expect(dayColor(11), Paper.mood[3]);
    expect(dayColor(12), Paper.mood[1]);
    await tester.tap(find.bySemanticsLabel('收起心情筛选'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test('全选首次点击只选此项，之后增减，取消最后一项恢复全部', () {
    var selected = Set<int>.of(allMoodScores);
    selected = selectMoodScore(selected, 4);
    expect(selected, {4});
    selected = selectMoodScore(selected, 3);
    expect(selected, {3, 4});
    selected = selectMoodScore(selected, 4);
    expect(selected, {3});
    selected = selectMoodScore(selected, 3);
    expect(selected, allMoodScores);
    expect(selectMoodScore(selected, 0), {0});
  });

  test('5至0从正上方逆时针每30度，44圆形点击范围不重叠', () {
    expect(moodFanOffset(5).dx, closeTo(0, 1e-8));
    expect(moodFanOffset(5).dy, -86);
    for (var score = 5; score > 0; score--) {
      final a = moodFanOffset(score);
      final b = moodFanOffset(score - 1);
      expect((a - b).distance, greaterThan(44));
      expect(a.dx * b.dy - a.dy * b.dx, lessThan(0));
      expect((a - b).distance, closeTo(172 * math.sin(math.pi / 12), 1e-8));
    }
  });

  for (final width in [320.0, 390.0]) {
    testWidgets('$width宽半圆多选，无恢复按钮，关闭重开保留筛选', (tester) async {
      tester.view.physicalSize = Size(width, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Set<int> selected = Set.of(allMoodScores);
      await tester.pumpWidget(
        MaterialApp(
          theme: Paper.theme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, update) => Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 150, right: 24),
                  child: MoodSemicircleFilter(
                    selected: selected,
                    onChanged: (v) => update(() => selected = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('心情筛选'));
      await tester.pumpAndSettle();
      expect(find.text('恢复全部'), findsNothing);
      final center = tester.getCenter(find.bySemanticsLabel('收起心情筛选'));
      for (var score = 0; score < 6; score++) {
        final target = find.bySemanticsLabel('筛选心情 $score 分');
        final rect = tester.getRect(target);
        expect(rect.width, 44);
        expect(rect.height, 44);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(568));
        expect(
          (tester.getCenter(target) - center - moodFanOffset(score)).distance,
          lessThan(1e-7),
        );
      }
      await tester.tap(find.bySemanticsLabel('筛选心情 4 分'));
      await tester.pumpAndSettle();
      expect(selected, {4});
      await tester.tap(find.bySemanticsLabel('筛选心情 3 分'));
      await tester.pumpAndSettle();
      expect(selected, {3, 4});
      await tester.tap(find.bySemanticsLabel('筛选心情 4 分'));
      await tester.pumpAndSettle();
      expect(selected, {3});
      await tester.tapAt(const Offset(10, 500));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('筛选心情 3 分'), findsNothing);
      await tester.tap(find.bySemanticsLabel('心情筛选'));
      await tester.pumpAndSettle();
      expect(selected, {3});
      await tester.tap(find.bySemanticsLabel('筛选心情 3 分'));
      await tester.pumpAndSettle();
      expect(selected, allMoodScores);
      await tester.tap(find.bySemanticsLabel('收起心情筛选'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
