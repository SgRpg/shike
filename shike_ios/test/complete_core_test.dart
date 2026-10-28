import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shike/src/store.dart';
import 'package:shike/complete/model.dart';
import 'package:shike/complete/persistence.dart';
import 'package:shike/complete/journal_repository.dart';
import 'package:shike/complete/reward_engine.dart';
import 'package:shike/complete/legacy_migration.dart';
import 'package:shike/refined/controller.dart' show PreviewStore;

Diary diary(
  String id,
  DateTime date, {
  String text = '今天的风很轻',
  String state = 'done',
  DateTime? unlock,
  int mood = 4,
  List<String> photos = const [],
  String? audio,
}) => Diary(
  id: id,
  text: text,
  mood: mood,
  created: date,
  updated: date,
  state: state,
  unlockAt: unlock,
  photos: photos,
  audio: audio,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryPersistence disk;
  late AtomicState db;
  late JournalRepository repo;
  late DateTime now;
  setUp(() async {
    disk = MemoryPersistence();
    db = await AtomicState.open(disk);
    now = DateTime(2026, 10, 28, 12);
    repo = JournalRepository(db, clock: () => now);
  });
  test('completion commits references, ordered media, metadata and durable event together', () async {
    await repo.commitCompleted(diary('target', now));
    const link = SentenceLink(
      id: 'r',
      source: 'draft',
      target: 'target',
      quote: '风很轻',
      start: 3,
      end: 6,
    );
    await repo.saveDraft(
      diary('draft', now, state: 'draft'),
      position: {'cursor': 3, 'scroll': 90},
    );
    final event = await repo.commitCompleted(
      diary('draft', now, photos: ['b', 'a'], audio: 'voice'),
      links: [link],
      metadata: '成都 · 晴',
    );
    final restarted = JournalRepository(await AtomicState.open(disk));
    expect(restarted.snapshot.events[event.id], isNotNull);
    expect(restarted.links('draft').single.id, 'r');
    expect(restarted.snapshot.media.keys, containsAll(['a', 'b', 'voice']));
    expect(restarted.snapshot.snapshots['draft'], '成都 · 晴');
    expect(restarted.snapshot.drafts, isNot(contains('draft')));
    await expectLater(
      repo.commitCompleted(diary('draft', now, text: '覆盖')),
      throwsStateError,
    );
  });
  test('failed transaction exposes no partial diary, media or event and queue recovers', () async {
    disk.failNextWrite = true;
    await expectLater(
      repo.commitCompleted(diary('a', now, photos: ['photo'])),
      throwsStateError,
    );
    expect(repo.entries, isEmpty);
    expect(repo.snapshot.events, isEmpty);
    expect(repo.snapshot.media, isEmpty);
    await repo.commitCompleted(diary('b', now));
    expect(repo.entries.single.id, 'b');
  });
  test('UTF-16 emoji, cross-line ranges shift after insertion and invalidate only edited link', () {
    const text = '风🍃很轻\n回家的路';
    const r = SentenceLink(
      id: 'r',
      source: 's',
      target: 't',
      quote: '🍃很轻\n回家',
      start: 1,
      end: 8,
    );
    expect(r.fits(text), isTrue);
    final shifted = LinkEditing.rebase(text, '今天$text', [r]).single;
    expect(shifted.start, 3);
    expect(shifted.end, 10);
    expect(LinkEditing.rebase(text, '风🍃特别轻\n回家的路', [r]), isEmpty);
    const split = SentenceLink(
      id: 'bad',
      source: 's',
      target: 't',
      quote: '\ud83c',
      start: 1,
      end: 2,
    );
    expect(split.fits(text), isFalse);
  });
  test('overlap replaced, unrelated preserved, invalid nesting rejected', () {
    const a = SentenceLink(
      id: 'a',
      source: 's',
      target: 't',
      quote: 'abc',
      start: 0,
      end: 3,
    );
    const b = SentenceLink(
      id: 'b',
      source: 's',
      target: 'v',
      quote: 'bcde',
      start: 1,
      end: 5,
    );
    expect(LinkEditing.replace([a], b, 'abcdef').single.id, 'b');
    expect(
      () => LinkEditing.validate('s', 'abcdef', [a, b]),
      throwsArgumentError,
    );
  });
  test('capsule boundaries, release survives clock rollback, first open counted once', () async {
    expect(
      JournalVisibility.validUnlock(now, now.add(const Duration(minutes: 59))),
      isFalse,
    );
    expect(
      JournalVisibility.validUnlock(now, now.add(const Duration(hours: 1))),
      isTrue,
    );
    expect(
      JournalVisibility.validUnlock(now, DateTime(2036, 10, 28, 12)),
      isTrue,
    );
    expect(
      JournalVisibility.validUnlock(now, DateTime(2036, 10, 28, 12, 0, 1)),
      isFalse,
    );
    await repo.commitCompleted(
      diary(
        'c',
        now,
        state: 'capsule',
        unlock: now.add(const Duration(hours: 1)),
      ),
    );
    expect(repo.visible, isEmpty);
    expect(await repo.openCapsule('c'), isNull);
    now = now.add(const Duration(hours: 1));
    await repo.reconcileCapsules();
    expect(await repo.takeDueHint(), ['c']);
    expect(await repo.takeDueHint(), isEmpty);
    final event = await repo.openCapsule('c');
    expect(event!.data['count'], 1);
    now = now.subtract(const Duration(days: 2));
    await repo.reconcileCapsules();
    expect(repo.visible.single.id, 'c');
    expect(await repo.openCapsule('c'), isNull);
    expect(repo.snapshot.meta['capsulesOpened'], 1);
  });
  test('notifications have stable chronological nearest ordering and exclude released', () async {
    for (var i = 65; i > 0; i--) {
      await repo.commitCompleted(
        diary(
          '$i',
          now,
          state: 'capsule',
          unlock: now.add(Duration(hours: i)),
        ),
      );
    }
    expect(repo.nearestNotifications.take(60).length, 60);
    expect(repo.nearestNotifications.first.id, '1');
    expect(repo.nearestNotifications.take(60).last.id, '60');
  });
  test('reward evaluation idempotent and gathers multiple cards', () async {
    final event = await repo.commitCompleted(
      diary('all', now, text: '字' * 1000, photos: ['p'], audio: 'a'),
    );
    final engine = RewardEngine(db, lottery: () => 1);
    final cards = await engine.evaluate(event);
    expect(
      cards.map((c) => c['key']),
      containsAll([
        'length-1000',
        'first-photo',
        'first-audio',
        'all-media',
        'happy:2026-10',
      ]),
    );
    expect(
      cards.firstWhere((c) => c['key'] == 'first-audio')['description'],
      contains('约定的声音'),
    );
    expect(await engine.evaluate(event), isEmpty);
  });
  test('missing photo opportunity consumed permanently without consuming a resource', () async {
    final engine = RewardEngine(db, lottery: () => 1);
    for (var i = 1; i <= 3; i++) {
      now = DateTime(2026, 10, i, 12);
      await engine.evaluate(await repo.commitCompleted(diary('$i', now)));
    }
    expect(
      repo.snapshot.meta['rewardAttempts']['streak-3']['skipped'],
      'missing-photo',
    );
    await db.transaction(
      (s) => s.resources['p'] = {'kind': 'photo', 'available': true},
    );
    now = DateTime(2026, 10, 4, 12);
    await engine.evaluate(await repo.commitCompleted(diary('4', now)));
    expect(repo.snapshot.grants.containsKey('streak-3'), isFalse);
    expect(repo.snapshot.resources['p']['used'], isNull);
  });
  test('gallery cumulative count survives deletion and only each new thirty triggers', () async {
    final engine = RewardEngine(db, lottery: () => 1);
    await db.transaction(
      (s) => s.resources['p'] = {'kind': 'photo', 'available': true},
    );
    for (var i = 0; i < 30; i++) {
      await engine.evaluate(await repo.importGallery('photo$i', 'path$i'));
    }
    expect(repo.snapshot.grants, contains('gallery:30'));
    await db.transaction((s) => s.gallery.clear());
    await engine.evaluate(await repo.importGallery('new', 'newpath'));
    expect(repo.snapshot.meta['galleryImported'], 31);
    expect(repo.snapshot.grants.length, 1);
  });
  test('remembered lottery one attempt daily and one grant weekly, other cards not capped', () async {
    final engine = RewardEngine(db, lottery: () => 0);
    for (var i = 0; i < 3; i++) {
      now = DateTime(2026, 10, 26 + i, 1);
      await engine.evaluate(
        await repo.commitCompleted(diary('d$i', now, photos: ['p'])),
      );
    }
    final grants = repo.snapshot.grants.values;
    expect(grants.where((c) => c['title'] == '被记住卡').length, 1);
    expect(grants.where((c) => c['title'] == '夜猫卡').length, 3);
    now = DateTime(2026, 11, 2, 1);
    await engine.evaluate(await repo.commitCompleted(diary('next', now)));
    expect(
      repo.snapshot.grants.values.where((c) => c['title'] == '被记住卡').length,
      2,
    );
  });
  test('opening rewards exactly at first, fourth, seventh', () async {
    final engine = RewardEngine(db, lottery: () => 1);
    for (var i = 1; i <= 7; i++) {
      final id = 'c$i';
      await repo.commitCompleted(
        diary(
          id,
          now,
          state: 'capsule',
          unlock: now.add(const Duration(hours: 1)),
        ),
      );
      now = now.add(const Duration(hours: 1));
      await repo.reconcileCapsules();
      await engine.evaluate((await repo.openCapsule(id))!);
    }
    expect(repo.snapshot.grants.keys.where((k) => k.startsWith('capsule:')), [
      'capsule:1',
      'capsule:4',
      'capsule:7',
    ]);
  });
  test(
    'one-time migration preserves legacy source and baselines old achievements',
    () async {
      SharedPreferences.setMockInitialValues({
        'rewards.cards': '[{"key":"old","title":"旧卡","description":"保留"}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final old = PreviewStore();
      for (var i = 1; i <= 14; i++) {
        await old.save(diary('$i', DateTime(2026, 10, i)));
      }
      await migrateLegacy(db, old, prefs);
      await migrateLegacy(db, old, prefs);
      expect(repo.entries.length, 14);
      expect(repo.snapshot.grants.keys, ['old']);
      expect(repo.snapshot.meta['legacyOriginal']['entries'].length, 14);
      expect(repo.snapshot.meta['rewardAttempts'], contains('total-14'));
      now = DateTime(2026, 10, 15);
      await RewardEngine(
        db,
        lottery: () => 1,
      ).evaluate(await repo.commitCompleted(diary('15', now)));
      expect(repo.snapshot.grants.containsKey('total-14'), isFalse);
    },
  );
}
