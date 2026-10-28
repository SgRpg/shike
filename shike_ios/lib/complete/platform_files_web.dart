import 'dart:convert';
import 'dart:typed_data';

import 'backup_service.dart';

Future<String> cachePrivatePhoto(String id, Uint8List bytes) async =>
    'data:image;base64,${base64Encode(bytes)}';

class PlatformBackupFiles extends MemoryBackupFiles {
  @override
  Future<Uint8List> read(String path) async =>
      path.startsWith('data:image;base64,')
      ? base64Decode(path.split(',').last)
      : super.read(path);
  @override
  String destination(String session, String name, Uint8List bytes) =>
      'data:image;base64,${base64Encode(bytes)}';
}

Future<BackupFiles> openBackupFiles() async => PlatformBackupFiles();
