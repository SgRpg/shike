import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shike/refined/design.dart';
import 'package:shike/refined/mood_nudge.dart';

void main() {
  testWidgets('心情色点从左到右波浪上浮后返回，连点不重启，无震动和文本弹层', (tester) async {
    final key = GlobalKey<MoodNudgeState>();
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MoodNudge(
              key: key,
              child: MoodChoices(value: null, onChanged: (_) {}),
            ),
          ),
        ),
      ),
    );
    final before = tester.getCenter(find.bySemanticsLabel('心情 0 分'));
    key.currentState!.nudge();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 112));
    final above = tester.getCenter(find.bySemanticsLabel('心情 0 分'));
    expect(above.dx, before.dx);
    expect(above.dy, closeTo(before.dy - 5, .03));
    key.currentState!.nudge();
    await tester.pump(const Duration(milliseconds: 509));
    expect(tester.getCenter(find.bySemanticsLabel('心情 0 分')), before);
    expect(find.text('记得选个心情哦'), findsNothing);
    expect(find.text('收好啦'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(haptics, 0);
  });

  testWidgets('减弱动态效果时保持色点静止', (tester) async {
    final key = GlobalKey<MoodNudgeState>();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: MoodNudge(
                key: key,
                child: MoodChoices(value: null, onChanged: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );
    key.currentState!.nudge();
    await tester.pump(const Duration(milliseconds: 112));
    final transform = tester.widget<Transform>(
      find.byKey(const ValueKey('mood-wave-dot-0')),
    );
    expect(transform.transform.getTranslation().y, 0);
    expect(tester.takeException(), isNull);
  });
}
