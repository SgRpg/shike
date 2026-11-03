import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shike/complete/controller.dart';
import 'package:shike/complete/editor.dart';
import 'package:shike/complete/journal_repository.dart';
import 'package:shike/complete/model.dart';
import 'package:shike/complete/persistence.dart';
import 'package:shike/complete/reference_picker.dart';
import 'package:shike/complete/reading.dart';
import 'package:shike/refined/design.dart';

import 'complete_core_test.dart' show diary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CompleteController controller;
  late JournalRepository repo;
  final now = DateTime(2026, 10, 28, 12);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = JournalRepository(
      await AtomicState.open(MemoryPersistence()),
      clock: () => now,
    );
    controller = CompleteController(CompleteStore(repo));
    await controller.initialize(loadAssets: false);
  });
  Future<void> pump(WidgetTester t, Widget page) async {
    t.view.physicalSize = const Size(402, 874);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(theme: Paper.theme(), home: page));
    await t.pumpAndSettle();
  }

  testWidgets(
    'draft editor restores selection and capsule date and uses exact selected-text menu',
    (t) async {
      final draft = diary(
        'draft',
        now,
        text: '今天🍃的风很轻',
        state: 'draft',
        unlock: now.add(const Duration(days: 1)),
      );
      await repo.saveDraft(
        draft,
        position: {'base': 2, 'extent': 4, 'scroll': 0},
      );
      await pump(t, RefinedEditor(controller: controller, draft: draft));
      final field = t.widget<TextField>(find.byKey(const Key('diary-body')));
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 2, extentOffset: 4),
      );
      await t.tap(find.byKey(const Key('diary-body')));
      await t.pump();
      field.controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 2,
      );
      final state = t.state<EditableTextState>(find.byType(EditableText));
      state.showToolbar();
      await t.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      expect(find.text('引用'), findsOneWidget);
      expect(find.text('删除引用'), findsNothing);
      expect(find.text('粘贴'), findsNothing);
      await t.tap(find.text('删除'));
      await t.pump(const Duration(milliseconds: 700));
      expect(field.controller!.text, '🍃的风很轻');
      expect(repo.entries.single.text, '🍃的风很轻');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 1));
    },
  );
  testWidgets(
    'picker hides drafts and locked capsules; preview returns preserving query',
    (t) async {
      await repo.commitCompleted(diary('ordinary', now, text: '花店旁的云'));
      await repo.commitCompleted(
        diary(
          'capsule',
          now,
          text: '秘密',
          state: 'capsule',
          unlock: now.add(const Duration(days: 1)),
        ),
      );
      await repo.saveDraft(diary('draft', now, text: '草稿', state: 'draft'));
      await pump(
        t,
        Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => chooseReference(c, controller, 'source'),
              child: const Text('选篇'),
            ),
          ),
        ),
      );
      await t.tap(find.text('选篇'));
      await t.pumpAndSettle();
      expect(find.text('花店旁的云'), findsOneWidget);
      expect(find.text('秘密'), findsNothing);
      expect(find.text('草稿'), findsNothing);
      await t.enterText(find.byType(TextField), '云');
      await t.pumpAndSettle();
      await t.tap(find.text('花店旁的云'));
      await t.pumpAndSettle();
      expect(find.text('返回列表'), findsOneWidget);
      expect(find.text('引用这篇'), findsOneWidget);
      await t.tap(find.text('返回列表'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, '云');
      expect(find.text('引用'), findsOneWidget);
    },
  );
  testWidgets(
    'linked text keeps body color with dashed underline and source breadcrumb',
    (t) async {
      await repo.commitCompleted(diary('target', now, text: '目的地'));
      await repo.commitCompleted(
        diary('source', now, text: '另一篇'),
        links: [
          const SentenceLink(
            id: 'r',
            source: 'source',
            target: 'target',
            quote: '另一篇',
            start: 0,
            end: 3,
          ),
        ],
      );
      await pump(
        t,
        ReadingPage(
          controller: controller,
          entry: controller.visible.firstWhere((d) => d.id == 'source'),
        ),
      );
      final rich = t.widget<SelectableText>(find.byType(SelectableText).first);
      final span = (rich.textSpan!.children!.firstWhere(
        (s) => s is TextSpan && s.recognizer != null,
      ) as TextSpan);
      expect(span.style!.color, isNull);
      expect(span.style!.decorationStyle, TextDecorationStyle.dashed);
      await t.tapAt(
        t.getTopLeft(find.byType(SelectableText).first) + const Offset(20, 14),
      );
      await t.pumpAndSettle();
      expect(find.text('回到 10月28日'), findsOneWidget);
      expect(find.text('目的地'), findsOneWidget);
      expect(
        referenceReturnLabel(DateTime(2025, 10, 28), now),
        '回到 2025年10月28日',
      );
    },
  );
}
