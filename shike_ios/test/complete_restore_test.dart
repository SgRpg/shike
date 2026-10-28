import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shike/complete/backup_service.dart';
import 'package:shike/complete/journal_repository.dart';
import 'package:shike/complete/persistence.dart';
import 'package:shike/complete/reward_engine.dart';

import 'complete_core_test.dart' show diary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 28, 12);
  test('repeated restore skips unchanged attachments and gallery without new files', () async {
    final db = await AtomicState.open(MemoryPersistence());
    final repo = JournalRepository(db, clock: () => now);
    final files = MemoryBackupFiles()
      ..files['image'] = Uint8List.fromList([1, 2, 3]);
    await repo.commitCompleted(diary('same', now, photos: ['image']));
    await repo.importGallery('p', 'image');
    final api = BackupService(db, files);
    final bytes = await api.export();
    final plan = await api.prepareImport(bytes);
    expect(plan.media, isEmpty);
    expect(plan.gallerySkips, contains('p'));
    await api.applyImport(plan);
    expect(files.files.length, 1);
    expect(repo.entries.length, 1);
    expect(db.snapshot.gallery.length, 1);
  });
  test(
    'backup restore preserves remembered weekly cap across historical weeks',
    () async {
      final db = await AtomicState.open(MemoryPersistence());
      await db.transaction(
        (s) => s.meta['rememberedWeeks'] = {
          '2026-10-26': true,
          '2026-10-19': true,
        },
      );
      final bytes = await BackupService(db, MemoryBackupFiles()).export();
      final target = await AtomicState.open(MemoryPersistence());
      final repo = JournalRepository(target, clock: () => now);
      final api = BackupService(target, MemoryBackupFiles());
      await api.applyImport(await api.prepareImport(bytes));
      final engine = RewardEngine(target, lottery: () => 0);
      await engine.evaluate(await repo.commitCompleted(diary('new', now)));
      expect(
        target.snapshot.grants.values.where((c) => c['title'] == '被记住卡'),
        isEmpty,
      );
    },
  );
}
