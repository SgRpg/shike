import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shike/complete/controller.dart';
import 'package:shike/complete/cards.dart';
import 'package:shike/complete/journal_repository.dart';
import 'package:shike/complete/persistence.dart';
import 'package:shike/refined/design.dart';

import 'complete_core_test.dart' show diary;

void main() {
  testWidgets(
    'completion batch survives editor pop and opens every card from this save',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final repo = JournalRepository(
        await AtomicState.open(MemoryPersistence()),
      );
      final controller = CompleteController(CompleteStore(repo));
      await controller.initialize(loadAssets: false);
      final d = diary(
        'entry',
        DateTime.now(),
        text: '字' * 1000,
        photos: ['photo'],
        audio: 'voice',
      );
      await repo.commitCompleted(d);
      await t.pumpWidget(
        MaterialApp(
          theme: Paper.theme(),
          home: Scaffold(
            body: Builder(
              builder: (home) => TextButton(
                onPressed: () => Navigator.push(
                  home,
                  MaterialPageRoute(
                    builder: (page) => Scaffold(
                      body: TextButton(
                        onPressed: () {
                          unawaited(completionFeedback(page, controller, d));
                          Navigator.pop(page);
                        },
                        child: const Text('保存完成'),
                      ),
                    ),
                  ),
                ),
                child: const Text('写作'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('写作'));
      await t.pumpAndSettle();
      await t.tap(find.text('保存完成'));
      await t.pumpAndSettle();
      expect(controller.cards.length, greaterThan(1));
      expect(find.text('这次有 ${controller.cards.length} 张小刻痕'), findsOneWidget);
      await t.tap(find.text('这次有 ${controller.cards.length} 张小刻痕'));
      await t.pumpAndSettle();
      expect(find.text('这次的小刻痕'), findsOneWidget);
      for (final card in controller.cards) {
        await t.scrollUntilVisible(
          find.text(card.title),
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(find.text(card.title), findsOneWidget);
      }
      await t.pump(const Duration(seconds: 7));
      await t.pumpWidget(const SizedBox());
    },
  );
}
