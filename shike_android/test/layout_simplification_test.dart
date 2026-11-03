import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shike/refined/controller.dart';
import 'package:shike/refined/semicircle_filter.dart';
import 'package:shike/refined/shell.dart';

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('首页不显示日期，角落无品牌重复文案且功能入口完整', (tester) async {
    phone(tester);
    final controller = RefinedController(PreviewStore(), demo: true);
    await tester.pumpWidget(RefinedApp(controller: controller));
    expect(find.text('拾刻'), findsOneWidget);
    expect(find.text(controller.metadata(DateTime.now())), findsNothing);
    expect(find.text('心情'), findsNothing);
    expect(find.text('收好'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tab-3')));
    await tester.pumpAndSettle();
    expect(find.text('拾刻'), findsNothing);
    expect(find.text('把此刻轻轻拾起'), findsNothing);
    for (final title in ['拾影', '卡包', '备份与迁移', '显示与权限', '关于拾刻']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('实际心迹页顶部切换位于四分之一和四分之三处且能切换', (tester) async {
    phone(tester);
    final controller = RefinedController(PreviewStore(), demo: true);
    await tester.pumpWidget(RefinedApp(controller: controller));
    await tester.tap(find.byKey(const ValueKey('tab-2')));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(const ValueKey('heart-top-label-false'))).dx,
      97.5,
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('heart-top-label-true'))).dx,
      292.5,
    );
    await tester.tap(find.text('热力图'));
    await tester.pumpAndSettle();
    expect(find.byType(MoodSemicircleFilter), findsOneWidget);
    await tester.tap(find.text('趋势'));
    await tester.pumpAndSettle();
    expect(find.text('每日平均心情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
