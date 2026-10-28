import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shike/refined/mood_wave.dart';

Widget dots() => Row(
  children: List.generate(
    6,
    (i) => MoodWaveDot(
      index: i,
      child: SizedBox(key: ValueKey('test-dot-$i'), width: 44, height: 48),
    ),
  ),
);

void main() {
  testWidgets('色点从第一个开始，每60ms依次到达顶点，整道波浪后归位', (tester) async {
    final key = GlobalKey<MoodWaveState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MoodWave(key: key, child: dots()),
          ),
        ),
      ),
    );
    final before = List.generate(
      6,
      (i) => tester.getCenter(find.byKey(ValueKey('test-dot-$i'))),
    );
    key.currentState!.nudge();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 112));
    expect(
      tester.getCenter(find.byKey(const ValueKey('test-dot-0'))).dy,
      closeTo(before[0].dy - 5, .03),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('test-dot-5'))),
      before[5],
    );
    for (var i = 1; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester.getCenter(find.byKey(ValueKey('test-dot-$i'))).dy,
        closeTo(before[i].dy - 5, .03),
      );
      expect(
        tester.getCenter(find.byKey(ValueKey('test-dot-${i - 1}'))).dy,
        greaterThan(before[i - 1].dy - 4.8),
      );
    }
    await tester.pump(const Duration(milliseconds: 209));
    for (var i = 0; i < 6; i++) {
      expect(tester.getCenter(find.byKey(ValueKey('test-dot-$i'))), before[i]);
    }
  });

  testWidgets('连续触发不会重启，减弱动态效果不播放，无作用域时静止', (tester) async {
    final key = GlobalKey<MoodWaveState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoodWave(key: key, child: dots()),
        ),
      ),
    );
    key.currentState!.nudge();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 112));
    final progress = key.currentState!.animation.value;
    key.currentState!.nudge();
    expect(key.currentState!.animation.value, progress);
    await tester.pump(const Duration(milliseconds: 509));
    expect(key.currentState!.animation.isCompleted, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: MoodWave(key: key, child: dots()),
          ),
        ),
      ),
    );
    key.currentState!.nudge();
    await tester.pump(const Duration(milliseconds: 112));
    expect(key.currentState!.animation.isAnimating, isFalse);
    for (var i = 0; i < 6; i++) {
      final t = tester.widget<Transform>(
        find.byKey(ValueKey('mood-wave-dot-$i')),
      );
      expect(t.transform.getTranslation().y, 0);
    }
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: dots())));
    expect(
      tester
          .widget<Transform>(find.byKey(const ValueKey('mood-wave-dot-3')))
          .transform
          .getTranslation()
          .y,
      0,
    );
    expect(tester.takeException(), isNull);
  });
}
