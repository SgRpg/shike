import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'controller.dart';
import 'model.dart';

/// Persist the destination before leaving the process for the Android picker.
/// Stable IDs make a resumed gallery import count each photo only once.
class AndroidPhotoImport {
  static const pendingKey = 'androidPhotoImport';

  static Future<List<String>> pick(
    CompleteController controller, {
    String? diaryId,
  }) async {
    await recover(controller);
    if (controller.repository.snapshot.meta[pendingKey] != null) {
      throw StateError('上一批照片仍待恢复');
    }
    final pending = <String, dynamic>{
      'ticket': controller.store.newId(),
      'diary': diaryId,
      'files': <String>[],
    };
    await controller.repository.state.transaction(
      (s) => s.meta[pendingKey] = pending,
    );
    final files = await ImagePicker().pickMultiImage(
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 88,
    );
    await controller.repository.state.transaction((s) {
      s.meta[pendingKey] = {
        ...pending,
        'files': files.map((f) => f.path).toList(),
      };
    });
    return _finish(controller);
  }

  static Future<void> recover(
    CompleteController controller, {
    Future<LostDataResponse> Function()? retrieve,
  }) async {
    final lost = await (retrieve ?? ImagePicker().retrieveLostData)();
    final current = controller.repository.snapshot.meta[pendingKey];
    if (current == null) return;
    if (lost.files?.isNotEmpty == true) {
      await controller.repository.state.transaction((s) {
        s.meta[pendingKey] = {
          ...Json.from(current),
          'files': lost.files!.map((f) => f.path).toList(),
        };
      });
    }
    await _finish(controller);
  }

  static Future<List<String>> _finish(CompleteController controller) async {
    final raw = controller.repository.snapshot.meta[pendingKey];
    if (raw == null) return [];
    final pending = Json.from(raw);
    final files = List<String>.from(pending['files']);
    final paths = <String>[];
    final directory = Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'images'),
    );
    await directory.create(recursive: true);
    for (var i = 0; i < files.length; i++) {
      final id = '${pending['ticket']}-$i';
      final extension = p.extension(files[i]).toLowerCase();
      final safeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
          ? extension
          : '.jpg';
      final target = File(p.join(directory.path, '$id$safeExtension'));
      if (!await target.exists()) {
        final temporary = File('${target.path}.part');
        await File(files[i]).copy(temporary.path);
        await temporary.rename(target.path);
      }
      paths.add(target.path);
      final diaryId = pending['diary'] as String?;
      final diary = controller.repository.snapshot.entries[diaryId];
      if (diaryId != null && diary != null && diary['state'] == 'draft') {
        await controller.repository.state.transaction((s) {
          final value = Json.from(s.entries[diaryId]!);
          final photos = List<String>.from(value['photos'] ?? []);
          if (!photos.contains(target.path)) photos.add(target.path);
          value['photos'] = photos;
          s.entries[diaryId] = value;
          s.media[target.path] = {'path': target.path, 'kind': 'image'};
        });
      } else {
        final event = await controller.repository.importGallery(
          id,
          target.path,
        );
        try {
          controller.unpresented.addAll(
            await controller.engine.evaluate(event),
          );
        } catch (_) {
          /* The durable event is retried at next startup. */
        }
      }
    }
    await controller.repository.state.transaction(
      (s) => s.meta.remove(pendingKey),
    );
    (controller.store as CompleteStore).refresh();
    controller.reload();
    return paths;
  }
}
