import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shike/complete/backup_service.dart';
import 'package:shike/complete/journal_repository.dart';
import 'package:shike/complete/model.dart';
import 'package:shike/complete/persistence.dart';
import 'package:shike/complete/nearby_protocol.dart';

import 'complete_core_test.dart' show diary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 28, 12);
  late AtomicState db;
  late JournalRepository repo;
  late MemoryBackupFiles files;
  late BackupService backups;
  setUp(() async {
    db = await AtomicState.open(MemoryPersistence());
    repo = JournalRepository(db, clock: () => now);
    files = MemoryBackupFiles();
    backups = BackupService(db, files, clock: () => now);
  });
  Future<Uint8List> sample() async {
    files.files['photo'] = Uint8List.fromList([1, 2, 3]);
    files.files['voice'] = Uint8List.fromList([4, 5]);
    await repo.commitCompleted(diary('target', now, text: '远方'));
    await repo.saveDraft(
      diary(
        'source',
        now,
        state: 'draft',
        text: '回到远方',
        photos: ['photo'],
        audio: 'voice',
      ),
      links: [
        const SentenceLink(
          id: 'ref',
          source: 'source',
          target: 'target',
          quote: '远方',
          start: 2,
          end: 4,
        ),
      ],
      position: {'base': 4, 'extent': 4, 'scroll': 45},
      metadata: '成都',
    );
    await db.transaction((s) {
      s.settings['city'] = '成都';
      s.meta['galleryImported'] = 31;
      s.grants['old'] = {'key': 'old', 'title': '旧卡', 'description': '保留'};
      s.resources['used'] = {'used': true, 'kind': 'photo'};
    });
    return backups.export();
  }

  test('versioned ZIP round-trip includes drafts, references, metadata, media and usage', () async {
    final bytes = await sample();
    final target = await AtomicState.open(MemoryPersistence()),
        destination = MemoryBackupFiles();
    final api = BackupService(target, destination, clock: () => now);
    final plan = await api.prepareImport(bytes);
    expect(plan.additions, 2);
    await api.applyImport(plan);
    final s = target.snapshot;
    expect(s.entries.length, 2);
    expect(s.links['source'].single['id'], 'ref');
    expect(s.drafts['source']['scroll'], 45);
    expect(s.snapshots['source'], '成都');
    expect(s.settings['city'], '成都');
    expect(s.grants, contains('old'));
    expect(s.resources['used']['used'], true);
    expect(await destination.read(s.entries['source']['photos'].single), [
      1,
      2,
      3,
    ]);
    expect(s.meta['galleryImported'], 31);
    expect(s.events, isEmpty);
  });
  test('identical entries including attachments are skipped; changed IDs remap both link endpoints', () async {
    final bytes = await sample();
    expect((await backups.prepareImport(bytes)).duplicates, 2);
    final target = await AtomicState.open(MemoryPersistence()),
        destination = MemoryBackupFiles();
    final r = JournalRepository(target, clock: () => now);
    await r.commitCompleted(diary('target', now, text: '本地的另一篇'));
    await r.commitCompleted(diary('source', now, text: '另一篇正式日记'));
    await target.transaction((s) => s.settings['city'] = '杭州');
    final api = BackupService(target, destination, clock: () => now);
    final plan = await api.prepareImport(bytes);
    expect(plan.conflicts, 2);
    await api.applyImport(plan);
    final s = target.snapshot;
    expect(s.entries['target']['text'], '本地的另一篇');
    expect(s.entries.length, 4);
    expect(s.settings['city'], '杭州');
    final source = plan.idMap['source']!, targetId = plan.idMap['target']!;
    expect(s.links[source].single['source'], source);
    expect(s.links[source].single['target'], targetId);
  });
  test(
    'mid-file interruption rolls back new files and all database records',
    () async {
      final bytes = await sample();
      final target = await AtomicState.open(MemoryPersistence()),
          destination = MemoryBackupFiles()..failPromotion = 2;
      final api = BackupService(target, destination, clock: () => now);
      final plan = await api.prepareImport(bytes);
      await expectLater(api.applyImport(plan), throwsStateError);
      expect(target.snapshot.entries, isEmpty);
      expect(target.snapshot.meta['importSession'], isNull);
      expect(destination.files, isEmpty);
    },
  );
  test(
    'restart cleans incomplete import only, leaves unrelated files intact',
    () async {
      files.files['mine'] = Uint8List.fromList([9]);
      files.files['staged'] = Uint8List(1);
      files.files['new'] = Uint8List(1);
      await db.transaction(
        (s) => s.meta['importSession'] = {
          'id': 'interrupted',
          'staged': ['staged'],
          'destinations': ['new'],
        },
      );
      await backups.recoverInterruptedImport();
      expect(files.files.keys, ['mine']);
      expect(db.snapshot.meta['importSession'], isNull);
    },
  );
  test('stale merge preview rejected before files or records change', () async {
    final bytes = await sample();
    final plan = await backups.prepareImport(bytes);
    await repo.commitCompleted(diary('after-preview', now));
    await expectLater(backups.applyImport(plan), throwsStateError);
    expect(repo.entries.length, 3);
  });
  test('legacy shike-backup JSON remains accepted with references', () async {
    final d = diary('legacy', now).toJson();
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'format': 'shike-backup',
          'version': 1,
          'entries': [d],
          'gallery': [],
          'cards': [],
          'references': {},
          'snapshots': {'legacy': '过去的天气'},
        }),
      ),
    );
    await backups.applyImport(await backups.prepareImport(bytes));
    expect(repo.entries.single.id, 'legacy');
    expect(db.snapshot.snapshots['legacy'], '过去的天气');
  });
  test('nearby frame handles fragmented packets, rejects corruption and interrupted stream', () {
    final payload = Uint8List.fromList(List.generate(200, (i) => i));
    final frame = NearbyFrame.encode(payload);
    final receiver = NearbyFrame();
    expect(receiver.add(frame.sublist(0, 7)), isNull);
    expect(receiver.add(frame.sublist(7, 25)), isNull);
    expect(receiver.add(frame.sublist(25)), payload);
    final corrupt = Uint8List.fromList(frame)..[20] = 255;
    expect(() => NearbyFrame().add(corrupt), throwsFormatException);
    expect(
      () => NearbyFrame().add(frame.sublist(0, 20), end: true),
      throwsFormatException,
    );
  });
  test(
    'pairing validates local IPv4, random key length and ten-minute expiry',
    () {
      final p = NearbyPairing(
        'id',
        '192.168.1.12',
        12345,
        NearbyPairing.secureKey(),
        now.add(const Duration(minutes: 10)),
      );
      expect(NearbyPairing.parse(p.encode(), now).port, 12345);
      expect(
        () => NearbyPairing.parse(
          p.encode(),
          now.add(const Duration(minutes: 10)),
        ),
        throwsFormatException,
      );
      expect(
        () => NearbyPairing.parse(
          NearbyPairing('id', '1.1.1.1', 12345, p.key, p.expires).encode(),
          now,
        ),
        throwsFormatException,
      );
    },
  );
}
