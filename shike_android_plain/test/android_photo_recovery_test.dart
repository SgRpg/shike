import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shike/complete/android_photo_import.dart';
import 'package:shike/complete/controller.dart';
import 'package:shike/complete/journal_repository.dart';
import 'package:shike/complete/persistence.dart';

import 'complete_core_test.dart' show diary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late CompleteController controller;
  late JournalRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp(
      'shike-android-recovery-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => directory.path,
        );
    repo = JournalRepository(await AtomicState.open(MemoryPersistence()));
    controller = CompleteController(CompleteStore(repo));
    await controller.initialize(loadAssets: false);
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });
  test(
    'picker result after process death attaches to its original draft',
    () async {
      await repo.saveDraft(diary('original', DateTime.now(), state: 'draft'));
      final source = File('${directory.path}/picked.jpg');
      await source.writeAsBytes([1, 2, 3]);
      await repo.state.transaction(
        (s) => s.meta[AndroidPhotoImport.pendingKey] = {
          'ticket': 'ticket',
          'diary': 'original',
          'files': <String>[],
        },
      );
      await AndroidPhotoImport.recover(
        controller,
        retrieve: () async => LostDataResponse(
          files: [XFile(source.path)],
          type: RetrieveType.image,
        ),
      );
      final photos = List<String>.from(
        repo.snapshot.entries['original']!['photos'],
      );
    expect(photos, hasLength(1));
      expect(await File(photos.single).readAsBytes(), [1, 2, 3]);
      expect(repo.snapshot.gallery, isEmpty);
      expect(repo.snapshot.meta[AndroidPhotoImport.pendingKey], isNull);
    },
  );
  test('retry after import commit does not duplicate a photo or the cumulative import count', () async {
    final source = File('${directory.path}/picked.jpg');
    await source.writeAsBytes([4, 5, 6]);
    final pending = {
      'ticket': 'ticket',
      'diary': null,
      'files': [source.path],
    };
    await repo.state.transaction(
      (s) => s.meta[AndroidPhotoImport.pendingKey] = pending,
    );
    await AndroidPhotoImport.recover(
      controller,
      retrieve: () async => LostDataResponse.empty(),
    );
    await repo.state.transaction(
      (s) => s.meta[AndroidPhotoImport.pendingKey] = pending,
    );
    await AndroidPhotoImport.recover(
      controller,
      retrieve: () async => LostDataResponse.empty(),
    );
    expect(repo.snapshot.gallery.length, 1);
    expect(repo.snapshot.meta['galleryImported'], 1);
  });
}
