import 'dart:convert';

import 'package:archive/archive.dart' show getCrc32;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../refined/controller.dart' as previous;
import '../src/rewards.dart' show RewardCard;
import '../src/store.dart';
import 'journal_repository.dart';
import 'legacy_migration.dart';
import 'model.dart';
import 'persistence.dart';
import 'reward_engine.dart';
import 'notifications.dart';
import 'weather.dart';
import 'platform_files.dart';
export '../refined/controller.dart'
    show JournalReference, GalleryPhoto, MoodDay, dayKey, localDay, onDay;

class StableJournalReference extends previous.JournalReference {
  final String id;
  const StableJournalReference({
    required this.id,
    required super.target,
    required super.text,
    required super.start,
    required super.end,
  });
}

class PersistentDiary extends Diary {
  final bool released;
  PersistentDiary(Diary d, this.released)
    : super(
        id: d.id,
        text: d.text,
        mood: d.mood,
        created: d.created,
        updated: d.updated,
        state: d.state,
        unlockAt: d.unlockAt,
        photos: d.photos,
        audio: d.audio,
        capsuleDraft: d.capsuleDraft,
      );
  @override
  bool get lockedCapsule => state == 'capsule' && !released;
}

class CompleteStore extends ShikeStore {
  final JournalRepository repository;
  List<SentenceLink> Function(String id)? pendingLinks;
  String Function(Diary d)? pendingMetadata;
  CompleteStore(this.repository) {
    repository.addListener(refresh);
    refresh();
  }
  void refresh() {
    entries
      ..clear()
      ..addAll(
        repository.entries.map(
          (d) => PersistentDiary(d, repository.readable(d)),
        ),
      );
    notifyListeners();
  }

  @override
  Future<void> save(Diary value) async {
    final refs = pendingLinks?.call(value.id) ?? repository.links(value.id);
    if (value.state == 'draft') {
      await repository.saveDraft(
        value,
        links: refs,
        metadata: pendingMetadata?.call(value),
      );
    } else {
      await repository.commitCompleted(
        value,
        links: refs,
        metadata: pendingMetadata?.call(value),
      );
    }
  }

  @override
  Future<void> deleteDraft(String id) => repository.deleteDraft(id);
  @override
  void dispose() {
    repository.removeListener(refresh);
    super.dispose();
  }
}

class CompleteController extends previous.RefinedController {
  final JournalRepository repository;
  late final RewardEngine engine;
  late final CapsuleNotificationService notifications;
  final weather = WeatherService();
  final List<Json> unpresented = [];
  CompleteController(CompleteStore source, {super.demo = false})
    : repository = source.repository,
      super(source) {
    engine = RewardEngine(repository.state);
    notifications = CapsuleNotificationService(repository);
    source.pendingLinks = (id) => sentenceLinks(id);
    source.pendingMetadata = (d) => metadata(d.created);
    repository.addListener(reload);
  }
  static Future<CompleteController> open() async {
    final state = await AtomicState.open(await openPersistence());
    final prefs = await SharedPreferences.getInstance();
    if (state.snapshot.meta['legacyMigration'] != 1) {
      await migrateLegacy(state, await ShikeStore.open(), prefs);
    }
    final c = CompleteController(CompleteStore(JournalRepository(state)));
    await c.initialize();
    return c;
  }

  @override
  Future<void> initialize({bool loadAssets = true}) async {
    if (!demo) prefs = await SharedPreferences.getInstance();
    settings.addAll({'location': false});
    reload();
    if (loadAssets && !demo) {
      await loadPhotoPack();
    }
    await repository.reconcileCapsules();
    try {
      unpresented.addAll(await engine.processPending());
    } catch (_) {
      /* Saved data remains available. */
    }
    reload();
  }

  void reload() {
    final s = repository.snapshot;
    photos
      ..clear()
      ..addAll(
        s.gallery.values.indexed.map(
          (e) => previous.GalleryPhoto.fromJson(Json.from(e.$2), e.$1),
        ),
      );
    photos.sort((a, b) => b.imported.compareTo(a.imported));
    cards
      ..clear()
      ..addAll(s.grants.values.map((j) => RewardCard.fromJson(Json.from(j))));
    settings
      ..clear()
      ..addAll({
        'greeting': false,
        'city': '',
        'weather': false,
        'exportMood': true,
        'location': false,
      })
      ..addAll(s.settings);
    snapshots
      ..clear()
      ..addAll(s.snapshots.map((k, v) => MapEntry(k, v as String)));
    references
      ..clear()
      ..addAll(
        s.links.map(
          (k, v) => MapEntry(k, [
            for (final j in v)
              StableJournalReference(
                id: j['id'],
                target: j['target'],
                text: j['quote'],
                start: j['start'],
                end: j['end'],
              ),
          ]),
        ),
      );
    cardImages.clear();
    for (final card in s.grants.values) {
      final resource = s.resources[card['resource']];
      if (resource?['path'] != null) cardImages[card['key']] = resource['path'];
    }
    notifyListeners();
  }

  List<SentenceLink> sentenceLinks(String id) {
    final existing = repository.links(id);
    return [
      for (final r in references[id] ?? <previous.JournalReference>[])
        SentenceLink(
          id: r is StableJournalReference
              ? r.id
              : existing
                        .where(
                          (x) =>
                              x.start == r.start &&
                              x.end == r.end &&
                              x.target == r.target,
                        )
                        .firstOrNull
                        ?.id ??
                    const Uuid().v4(),
          source: id,
          target: r.target,
          quote: r.text,
          start: r.start,
          end: r.end,
        ),
    ];
  }

  @override
  Future<void> saveLinks(
    String id,
    List<previous.JournalReference> links,
  ) async {
    final entry = store.entries.where((e) => e.id == id).firstOrNull;
    if (entry == null || entry.state != 'draft') throw StateError('只能修改草稿引用');
    references[id] = List.of(links);
    await repository.saveDraft(
      entry,
      links: sentenceLinks(id),
      position: Json.from(repository.snapshot.drafts[id] ?? {}),
      metadata: snapshots[id],
    );
  }

  Future<void> saveEditing(
    Diary d,
    List<previous.JournalReference> links,
    Json position,
  ) async {
    references[d.id] = List.of(links);
    await repository.saveDraft(
      d,
      links: sentenceLinks(d.id),
      position: position,
      metadata: metadata(d.created),
    );
  }

  @override
  Future<void> snapshot(String id, String value) async {
    // Completion has already frozen metadata in its transaction.
    if (store.entries.where((d) => d.id == id).firstOrNull?.state != 'draft') {
      return;
    }
    await repository.state.transaction((s) => s.snapshots[id] = value);
    reload();
  }

  @override
  Future<List<RewardCard>> reward(Diary diary) async {
    if (demo) return [];
    final raw = repository.snapshot.events['completed:${diary.id}'];
    if (raw == null) return [];
    final added = await engine.evaluate(BusinessEvent.fromJson(Json.from(raw)));
    reload();
    return added.map(RewardCard.fromJson).toList();
  }

  Future<List<RewardCard>> opened(Diary diary) async {
    if (demo) return [];
    final event = await repository.openCapsule(diary.id);
    if (event == null) return [];
    final cards = await engine.evaluate(event);
    reload();
    return cards.map(RewardCard.fromJson).toList();
  }

  @override
  Future<void> addPhoto(String path) async {
    final event = await repository.importGallery(store.newId(), path);
    try {
      unpresented.addAll(await engine.evaluate(event));
    } catch (_) {
      /* Retry from durable outbox. */
    }
    reload();
  }

  @override
  Future<void> savePhotos() async {
    await repository.state.transaction((s) {
      s.gallery
        ..clear()
        ..addAll({for (final p in photos) p.id: p.toJson()});
    });
    reload();
  }

  @override
  Future<void> removePhoto(String id) async {
    await repository.state.transaction((s) => s.gallery.remove(id));
    reload();
  }

  @override
  Future<void> reloadCollections() async => reload();
  @override
  Future<void> setSetting(String key, dynamic value) async {
    await repository.state.transaction((s) => s.settings[key] = value);
    reload();
  }

  Future<void> reconcileNotifications({bool requestPermission = false}) async {
    if (demo) return;
    try {
      await notifications.reconcile(requestPermission: requestPermission);
    } catch (_) {
      /* Denied notifications never block writing. */
    }
  }

  Future<void> refreshWeather() async {
    if (settings['weather'] != true) return;
    final lat = settings['latitude'] as num?,
        lng = settings['longitude'] as num?;
    if (lat == null || lng == null) return;
    final value = await weather.fetch(lat.toDouble(), lng.toDouble());
    await repository.state.transaction((s) {
      s.meta['currentWeather'] = value;
    });
    reload();
  }

  @override
  String metadata(DateTime date) {
    final s = repository.snapshot;
    final weather = usableWeather(settings, s.meta, repository.clock());
    return [
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
      if (settings['weather'] == true && weather != null)
        '${weather['label']} ${weather['temperature']}°C',
      if (settings['location'] == true &&
          (settings['city'] as String).isNotEmpty)
        settings['city'] as String,
    ].join(' · ');
  }

  Future<void> loadPhotoPack() async {
    try {
      final j = Json.from(
        jsonDecode(await rootBundle.loadString('assets/private/manifest.json')),
      );
      if (j['version'] != 1) return;
      final loaded = <String, Json>{};
      for (final raw in j['photos'] as List) {
        final file = raw['file'] as String;
        if (file.contains('..') ||
            file.startsWith('/') ||
            file.contains('\\')) {
          continue;
        }
        final data = await rootBundle.load('assets/private/$file');
        final bytes = Uint8List.sublistView(data);
        // Package verification is performed by the Windows packer; the app
        // also rejects length mismatches before exposing a resource.
        if (bytes.length != raw['length'] || getCrc32(bytes) != raw['crc32']) {
          continue;
        }
        loaded[raw['id']] = {
          'kind': 'photo',
          'available': true,
          'path': await cachePrivatePhoto(raw['id'], bytes),
        };
      }
      await repository.state.transaction((s) {
        for (final r in loaded.entries) {
          s.resources[r.key] = {
            ...r.value,
            'used': s.resources[r.key]?['used'] == true,
          };
        }
      });
    } catch (_) {
      /* A build with no private pack is an intentional valid state. */
    }
  }

  @override
  void dispose() {
    repository.removeListener(reload);
    super.dispose();
  }
}
