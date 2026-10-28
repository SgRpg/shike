import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shike/refined/design.dart';
import 'package:shike/refined/heart_tabs.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('$width宽度两项各占一半，文字居中，下划线文字左右各12', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var heat = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: Paper.theme(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.8 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (c, update) => HeartTopTabs(
                heat: heat,
                onChanged: (v) => update(() => heat = v),
              ),
            ),
          ),
        ),
      );
      for (final value in [false, true]) {
        final option = find.byKey(ValueKey('heart-top-option-$value'));
        final label = find.byKey(ValueKey('heart-top-label-$value'));
        final line = find.byKey(ValueKey('heart-top-line-$value'));
        expect(tester.getSize(option).width, width / 2);
        expect(tester.getCenter(label).dx, width * (value ? .75 : .25));
        expect(
          tester.getSize(line).width,
          closeTo(tester.getSize(label).width + 24, .01),
        );
        expect(tester.getCenter(line).dx, tester.getCenter(label).dx);
        expect(tester.getSize(option).height, greaterThanOrEqualTo(44));
      }
      await tester.tapAt(Offset(width - 10, 20));
      await tester.pumpAndSettle();
      expect(heat, isTrue);
      await tester.tapAt(const Offset(10, 20));
      await tester.pumpAndSettle();
      expect(heat, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
