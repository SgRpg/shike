import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../src/store.dart';
import 'model.dart';
import 'persistence.dart';

/// The original SQLite database and preferences are read only, never removed.
Future<void> migrateLegacy(
  AtomicState state,
  ShikeStore legacy,
  SharedPreferences prefs,
) async {
  if (state.snapshot.meta['legacyMigration'] == 1) return;
  final keys = [
    'gallery.items',
    'rewards.cards',
    'rewards.randomWeek',
    'refined.settings',
    'refined.references',
    'refined.snapshots',
    'refined.cardImages',
  ];
  await state.transaction((s) {
    if (s.meta['legacyMigration'] == 1) return;
    final backup = <String, dynamic>{
      for (final key in keys) key: prefs.get(key),
    };
    s.meta['legacyOriginal'] = {
      'preferences': backup,
      'entries': legacy.entries.map((e) => e.toJson()).toList(),
    };
    for (final e in legacy.entries) {
      s.entries.putIfAbsent(e.id, e.toJson);
    }
    Json readMap(String key) =>
        Json.from(jsonDecode(prefs.getString(key) ?? '{}'));
    for (final item in readMap('refined.snapshots').entries) {
      s.snapshots.putIfAbsent(item.key, () => item.value);
    }
    s.settings.addAll(readMap('refined.settings'));
    for (final item in readMap('refined.references').entries) {
      final refs = (item.value as List).indexed
          .map(
            (r) => SentenceLink(
              id: 'legacy:${item.key}:${r.$1}',
              source: item.key,
              target: r.$2['target'],
              quote: r.$2['text'],
              start: r.$2['start'],
              end: r.$2['end'],
            ),
          )
          .toList();
      final text = s.entries[item.key]?['text'] as String? ?? '';
      s.links.putIfAbsent(
        item.key,
        () => refs.where((r) => r.fits(text)).map((r) => r.toJson()).toList(),
      );
    }
    final photos = jsonDecode(prefs.getString('gallery.items') ?? '[]') as List;
    for (final item in photos.indexed) {
      final j = Json.from(item.$2);
      final id = j['id'] as String? ?? 'legacy:${item.$1}';
      s.gallery.putIfAbsent(
        id,
        () => {
          ...j,
          'id': id,
          'imported':
              j['imported'] ??
              DateTime.fromMillisecondsSinceEpoch(1000000 - item.$1)
                  .toIso8601String(),
        },
      );
    }
    s.meta['galleryImported'] = photos.length;
    for (final card
        in jsonDecode(prefs.getString('rewards.cards') ?? '[]') as List) {
      s.grants.putIfAbsent(card['key'], () => card);
    }
    s.meta['randomWeek'] = normalizedWeek(
      prefs.getString('rewards.randomWeek'),
    );
    if (s.meta['randomWeek'] != null) {
      s.meta['rememberedWeeks'] = {s.meta['randomWeek']: true};
    }
    for (final image in readMap('refined.cardImages').entries) {
      final resource = 'legacy-card:${image.key}';
      s.resources[resource] = {
        'kind': 'photo',
        'used': true,
        'available': true,
        'path': image.value,
      };
      if (s.grants[image.key] != null) {
        s.grants[image.key]['resource'] = resource;
      }
    }
    for (final d in legacy.entries) {
      for (final file in [...d.photos, if (d.audio != null) d.audio!]) {
        s.media[file] = {
          'path': file,
          'kind': file == d.audio ? 'audio' : 'image',
        };
      }
    }
    // Baseline every previously achieved fixed rule; upgrading never emits a backlog.
    final old = legacy.entries.where((d) => d.state == 'done').toList();
    final days = old.map((d) => naturalDay(d.created)).toSet();
    final attempts = <String, dynamic>{};
    void mark(String key) => attempts[key] = {'skipped': 'legacy-baseline'};
    for (final count in [7, 10, 14, 30, 100]) {
      if (days.length >= count) mark('total-$count');
    }
    var longest = 0;
    for (final d in old) {
      var n = 0;
      var day = DateTime(d.created.year, d.created.month, d.created.day);
      while (days.contains(naturalDay(day))) {
        n++;
        day = DateTime(day.year, day.month, day.day - 1);
      }
      if (n > longest) longest = n;
    }
    for (final count in [3, 7, 14, 30]) {
      if (longest >= count) mark('streak-$count');
    }
    if (old.any(
      (d) => d.text.characters.length >= 500 && d.text.characters.length < 1000,
    )) {
      mark('length-500');
    }
    if (old.any((d) => d.text.characters.length >= 1000)) mark('length-1000');
    if (old.any((d) => d.photos.isNotEmpty)) mark('first-photo');
    if (old.any((d) => d.audio != null)) mark('first-audio');
    if (old.any((d) => d.photos.isNotEmpty && d.audio != null)) {
      mark('all-media');
    }
    for (var count = 30; count <= photos.length; count += 30) {
      mark('gallery:$count');
    }
    s.meta['rewardAttempts'] = attempts;
    s.meta['legacyMigration'] = 1;
  });
}
