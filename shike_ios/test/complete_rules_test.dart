import 'package:flutter_test/flutter_test.dart';
import 'package:lunar/lunar.dart';
import 'package:shike/complete/persistence.dart';
import 'package:shike/complete/journal_repository.dart';
import 'package:shike/complete/reward_engine.dart';
import 'package:shike/complete/model.dart';
import 'package:shike/complete/weather.dart';

import 'complete_core_test.dart' show diary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AtomicState db;
  late JournalRepository repo;
  late RewardEngine engine;
  late DateTime now;
  setUp(() async {
    db = await AtomicState.open(MemoryPersistence());
    now = DateTime(2026, 1, 1, 12);
    repo = JournalRepository(db, clock: () => now);
    engine = RewardEngine(db, lottery: () => 1);
    await db.transaction((s) {
      for (var i = 0; i < 10; i++)
        s.resources['photo$i'] = {'kind': 'photo', 'available': true};
    });
  });
  test('all cumulative and streak milestones; unique natural days; fixed grants do not repeat', () async {
    for (var i = 0; i < 101; i++) {
      now = DateTime(2026, 1, 1 + i, 12);
      await engine.evaluate(await repo.commitCompleted(diary('d$i', now)));
      if (i == 0)
        await engine.evaluate(
          await repo.commitCompleted(diary('same-day', now)),
        );
    }
    expect(
      db.snapshot.grants.keys,
      containsAll([
        'total-7',
        'total-10',
        'total-14',
        'total-30',
        'total-100',
        'streak-3',
        'streak-7',
        'streak-14',
        'streak-30',
      ]),
    );
    expect(
      db.snapshot.resources.values.where((p) => p['used'] == true).length,
      2,
    );
  });
  for (final count in [499, 500, 999, 1000]) {
    test('length boundary $count counts grapheme clusters', () async {
      final event = await repo.commitCompleted(
        diary('length', now, text: '🍃' * count),
      );
      await engine.evaluate(event);
      expect(
        db.snapshot.grants.containsKey('length-500'),
        count >= 500 && count < 1000,
      );
      expect(db.snapshot.grants.containsKey('length-1000'), count >= 1000);
    });
  }
  test(
    'monthly happy fraction must exceed sixty percent, at most once per month',
    () async {
      for (var i = 0; i < 4; i++) {
        await repo.commitCompleted(diary('seed$i', now, mood: i < 2 ? 4 : 0));
      }
      await engine.evaluate(
        await repo.commitCompleted(diary('sixty', now, mood: 4)),
      );
      expect(db.snapshot.grants.containsKey('happy:2026-1'), false);
      await engine.evaluate(
        await repo.commitCompleted(diary('higher', now, mood: 4)),
      );
      expect(
        db.snapshot.grants.keys.where((k) => k == 'happy:2026-1').length,
        1,
      );
    },
  );
  test('fixed Gregorian and lunar dates recur yearly without duplicate same-year cards', () async {
    now = DateTime(2026, 6, 30, 12);
    await engine.evaluate(await repo.commitCompleted(diary('june', now)));
    expect(db.snapshot.grants, contains('june30:2026'));
    for (final date in [(8, 18, 'birthday'), (10, 24, 'reminder')]) {
      final solar = Lunar.fromYmd(2026, date.$1, date.$2).getSolar();
      now = DateTime(solar.getYear(), solar.getMonth(), solar.getDay(), 12);
      await engine.evaluate(await repo.commitCompleted(diary(date.$3, now)));
      await engine.evaluate(
        await repo.commitCompleted(diary('${date.$3}-again', now)),
      );
      expect(
        db.snapshot.grants.keys.where((k) => k == '${date.$3}:2026').length,
        1,
      );
    }
    expect(db.snapshot.grants['birthday:2026']['description'], '生日快乐呀小宝');
  });
  test('contextual cards have once-per-eligible-day draws; frozen weather drives rain and snow', () async {
    engine = RewardEngine(db, lottery: () => 0);
    final cases = [
      (DateTime(2026, 10, 1, 1), 'night', null),
      (DateTime(2026, 10, 2, 5), 'morning', null),
      (DateTime(2026, 10, 3, 12), 'rain', 61),
      (DateTime(2026, 10, 4, 12), 'snow', 73),
      (DateTime(2026, 1, 1, 12), 'holiday', null),
    ];
    for (final c in cases) {
      now = c.$1;
      await db.transaction((s) {
        s.settings.addAll({
          'weather': true,
          'latitude': 31.2,
          'longitude': 121.5,
        });
        s.meta['currentWeather'] = {
          'fetchedAt': now.toIso8601String(),
          'cityKey': '31.2,121.5',
          'code': c.$3 ?? 0,
        };
      });
      await engine.evaluate(await repo.commitCompleted(diary(c.$2, now)));
      await engine.evaluate(
        await repo.commitCompleted(diary('${c.$2}-repeat', now)),
      );
      expect(
        db.snapshot.grants.keys.where((k) => k.startsWith('${c.$2}:')).length,
        1,
      );
    }
  });
  test(
    'reward failure leaves saved journal and pending event for restart retry',
    () async {
      final event = await repo.commitCompleted(
        diary('saved', now, photos: ['p']),
      );
      (db.persistence as MemoryPersistence).failNextWrite = true;
      await expectLater(engine.evaluate(event), throwsStateError);
      expect(repo.entries.single.id, 'saved');
      expect(db.snapshot.events[event.id]['processed'], isNull);
      expect(await engine.processPending(), isNotEmpty);
      expect(await engine.processPending(), isEmpty);
    },
  );
  test(
    'repeating text edit uses selection to retain the untouched stable link ID',
    () {
      const link = SentenceLink(
        id: 'stable',
        source: 's',
        target: 't',
        quote: 'a',
        start: 2,
        end: 3,
      );
      final result = LinkEditing.rebase(
        'aaa',
        'aa',
        [link],
        selectionStart: 0,
        selectionEnd: 1,
      ).single;
      expect(result.id, 'stable');
      expect(result.start, 1);
    },
  );
  test('weather rounds coordinates, caches fifteen minutes and returns null on failure', () async {
    var calls = 0;
    var clock = DateTime(2026, 10, 28, 12);
    final service = WeatherService(
      clock: () => clock,
      request: (method, args) async {
        calls++;
        expect(args['latitude'], 31.2);
        expect(args['longitude'], 121.5);
        if (calls > 1) throw StateError('offline');
        return {'weather_code': 0, 'temperature_2m': 18.2};
      },
    );
    final first = await service.fetch(31.23456, 121.45678);
    expect(first!['temperature'], 18);
    expect(await service.fetch(31.23456, 121.45678), first);
    expect(calls, 1);
    clock = clock.add(const Duration(minutes: 15));
    expect(await service.fetch(31.23456, 121.45678), isNull);
  });
  test(
    'stale or different-city weather never enters a completed snapshot',
    () async {
      now = DateTime(2026, 10, 28, 12);
      final settings = <String, dynamic>{
        'weather': true,
        'latitude': 31.2,
        'longitude': 121.5,
      };
      final cache = <String, dynamic>{
        'currentWeather': {
          'fetchedAt': now.toIso8601String(),
          'cityKey': '31.2,121.5',
          'code': 61,
        },
      };
      expect(usableWeather(settings, cache, now), isNotNull);
      expect(
        usableWeather(settings, cache, now.add(const Duration(minutes: 15))),
        isNull,
      );
      expect(
        usableWeather({...settings, 'latitude': 30.1}, cache, now),
        isNull,
      );
      await db.transaction((s) {
        s.settings.addAll(settings);
        s.meta.addAll(cache);
      });
      await repo.commitCompleted(diary('old', now), metadata: '晴 18°C · 成都');
      await db.transaction((s) {
        s.meta['currentWeather']['code'] = 73;
      });
      expect(db.snapshot.meta['weatherCodes']['old'], 61);
      expect(db.snapshot.snapshots['old'], '晴 18°C · 成都');
    },
  );
}
