import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_service.dart';

Future<String> cachePrivatePhoto(String id, Uint8List bytes) async {
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
    throw const FormatException('照片 ID 无效');
  }
  final file = File(
    p.join(
      (await getApplicationDocumentsDirectory()).path,
      'private-pool',
      '$id.img',
    ),
  );
  if (await file.exists()) {
    final old = await file.readAsBytes();
    if (old.length != bytes.length) {
      throw const FormatException('同一素材 ID 的照片已改变');
    }
    for (var i = 0; i < old.length; i++) {
      if (old[i] != bytes[i]) throw const FormatException('同一素材 ID 的照片已改变');
    }
  } else {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }
  return file.path;
}

class PlatformBackupFiles extends BackupFiles {
  final String root;
  PlatformBackupFiles(this.root);
  void verify(String path) {
    if (!p.isWithin(root, p.normalize(p.absolute(path)))) {
      throw StateError('附件路径无效');
    }
  }

  @override
  Future<Uint8List> read(String path) async =>
      path.startsWith('data:image;base64,')
      ? base64Decode(path.split(',').last)
      : await File(path).readAsBytes();
  @override
  Future<String> stage(String session, String name, Uint8List bytes) async {
    final path = stagedPath(session, name);
    verify(path);
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  String stagedPath(String session, String name) =>
      p.join(root, 'staging', session, name);
  @override
  String destination(String session, String name, Uint8List bytes) =>
      p.join(root, 'media', session, name);
  @override
  Future<void> promote(String staged, String destination) async {
    verify(staged);
    verify(destination);
    await File(destination).parent.create(recursive: true);
    await File(staged).rename(destination);
  }

  @override
  Future<void> remove(String path) async {
    verify(path);
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

Future<BackupFiles> openBackupFiles() async => PlatformBackupFiles(
  p.join((await getApplicationDocumentsDirectory()).path, 'complete-imports'),
);
