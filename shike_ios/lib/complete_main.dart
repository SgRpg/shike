import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'refined/art_data.dart';
import 'complete/visual_demo_entry.dart' as preview;
import 'complete/controller.dart';
import 'complete/shell.dart';
import 'complete/backup_service.dart';
import 'complete/platform_files.dart';
import 'complete/optimized_images.dart' show configurePhotoMemoryCache;

/// Explicit full-version entry. The existing main.dart remains untouched until
/// the user approves its one-line delegation change.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  configurePhotoMemoryCache();
  const demo = bool.fromEnvironment('SHIKE_VISUAL_DEMO');
  if (demo) {
    await preview.main();
    return;
  }
  final loader = FontLoader(
    'ShikeSerif',
  )..addFont(Future.value(ByteData.sublistView(base64Decode(titleFontBase64))));
  await loader.load();
  LicenseRegistry.addLicense(
    () => Stream.value(
      LicenseEntryWithLineBreaks([
        'Noto Serif SC',
      ], utf8.decode(base64Decode(titleFontLicenseBase64))),
    ),
  );
  final controller = await CompleteController.open();
  await BackupService(
    controller.repository.state,
    await openBackupFiles(),
  ).recoverInterruptedImport();
  unawaited(controller.reconcileNotifications());
  unawaited(controller.refreshWeather());
  runApp(RefinedApp(controller: controller));
}
