import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'shell.dart';
import 'model.dart';
import 'persistence.dart';
import 'journal_repository.dart';
import '../refined/art_data.dart';
import '../refined/fixtures.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  final fixture = visualFixture();
  final state = await AtomicState.open(MemoryPersistence());
  await state.transaction((s) {
    s.entries.addAll({for (final d in fixture.store.entries) d.id: d.toJson()});
    s.gallery.addAll({for (final p in fixture.photos) p.id: p.toJson()});
    s.grants.addAll({
      for (final card in fixture.cards) card.key: card.toJson(),
    });
    s.links['fixture-evening'] = [
      SentenceLink(
        id: 'demo-ref',
        source: 'fixture-evening',
        target: 'fixture-0',
        quote: '风很舒服',
        start: 3,
        end: 7,
      ).toJson(),
    ];
  });
  final controller = CompleteController(
    CompleteStore(JournalRepository(state)),
    demo: true,
  );
  await controller.initialize(loadAssets: false);
  runApp(RefinedApp(controller: controller));
}
