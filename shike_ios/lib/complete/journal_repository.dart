import 'package:flutter/foundation.dart';

import '../src/store.dart';
import 'model.dart';
import 'persistence.dart';

class JournalRepository extends ChangeNotifier {
  final AtomicState state;
  final DateTime Function() clock;
  JournalRepository(this.state, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  JournalState get snapshot => state.snapshot;
  List<Diary> get entries =>
      snapshot.entries.values.map((j) => Diary.fromJson(Json.from(j))).toList()
        ..sort((a, b) => b.created.compareTo(a.created));
  bool readable(Diary d) => JournalVisibility.readable(
    d,
    Json.from(snapshot.capsules[d.id] ?? {}),
    clock(),
  );
  List<Diary> get visible => entries.where(readable).toList();
  List<SentenceLink> links(String id) => [
    for (final j in snapshot.links[id] ?? [])
      SentenceLink.fromJson(Json.from(j)),
  ];

  Future<void> saveDraft(
    Diary d, {
    List<SentenceLink> links = const [],
    Json position = const {},
    String? metadata,
  }) async {
    if (d.state != 'draft') throw ArgumentError('不是草稿');
    LinkEditing.validate(d.id, d.text, links);
    await state.transaction((s) {
      _mutable(s, d.id);
      s.entries[d.id] = d.toJson();
      s.links[d.id] = links.map((r) => r.toJson()).toList();
      s.drafts[d.id] = position;
      if (metadata != null) s.snapshots[d.id] = metadata;
      _registerMedia(s, d);
    });
    notifyListeners();
  }

  Future<BusinessEvent> commitCompleted(
    Diary d, {
    List<SentenceLink> links = const [],
    String? metadata,
    String? timezone,
  }) async {
    if (!['done', 'completed', 'capsule'].contains(d.state) ||
        d.text.trim().isEmpty ||
        d.mood == null) {
      throw ArgumentError('请完成正文和心情');
    }
    if (d.state == 'capsule' &&
        (d.unlockAt == null ||
            !JournalVisibility.validUnlock(clock(), d.unlockAt!))) {
      throw ArgumentError('请设置一小时到十年内的开启时间');
    }
    LinkEditing.validate(d.id, d.text, links);
    final event = BusinessEvent('completed:${d.id}', 'completed', clock(), {
      'journal': d.id,
    });
    await state.transaction((s) {
      _mutable(s, d.id);
      for (final r in links) {
        final target = s.entries[r.target];
        if (target == null ||
            !JournalVisibility.eligibleTarget(
              Diary.fromJson(Json.from(target)),
              Json.from(s.capsules[r.target] ?? {}),
              clock(),
            )) {
          throw ArgumentError('引用目标尚不可读');
        }
      }
      s.entries[d.id] = d.toJson();
      s.links[d.id] = links.map((r) => r.toJson()).toList();
      s.snapshots[d.id] = metadata ?? s.snapshots[d.id] ?? '';
      final weather = usableWeather(s.settings, s.meta, clock());
      if (weather != null) {
        final codes = Json.from(s.meta['weatherCodes'] ?? {});
        codes[d.id] = weather['code'];
        s.meta['weatherCodes'] = codes;
      }
      s.drafts.remove(d.id);
      _registerMedia(s, d);
      if (d.state == 'capsule') {
        s.capsules[d.id] = {
          'zone': timezone ?? clock().timeZoneName,
          'createdOffsetMinutes': clock().timeZoneOffset.inMinutes,
          'unlockUtc': d.unlockAt!.toUtc().toIso8601String(),
        };
      }
      s.events[event.id] = event.toJson();
    });
    notifyListeners();
    return event;
  }

  void _mutable(JournalState s, String id) {
    if (s.entries[id] != null && s.entries[id]['state'] != 'draft') {
      throw StateError('已完成的日记不可修改');
    }
  }

  void _registerMedia(JournalState s, Diary d) {
    for (final item in [...d.photos, if (d.audio != null) d.audio!]) {
      s.media[item] = {
        'path': item,
        'kind': item == d.audio ? 'audio' : 'image',
      };
    }
  }

  Future<void> deleteDraft(String id) async {
    await state.transaction((s) {
      if (s.entries[id]?['state'] != 'draft') return;
      s.entries.remove(id);
      s.links.remove(id);
      s.drafts.remove(id);
      s.snapshots.remove(id);
    });
    notifyListeners();
  }

  Future<void> reconcileCapsules() async {
    await state.transaction((s) {
      for (final raw in s.entries.values) {
        final d = Diary.fromJson(Json.from(raw));
        if (d.state == 'capsule' &&
            d.unlockAt != null &&
            !clock().toUtc().isBefore(d.unlockAt!.toUtc())) {
          final flags = Json.from(s.capsules[d.id] ?? {});
          flags.putIfAbsent(
            'releasedAt',
            () => clock().toUtc().toIso8601String(),
          );
          s.capsules[d.id] = flags;
        }
      }
    });
    notifyListeners();
  }

  Future<BusinessEvent?> openCapsule(String id) async {
    final event = await state.transaction<BusinessEvent?>((s) {
      final raw = s.entries[id];
      if (raw == null) return null;
      final d = Diary.fromJson(Json.from(raw));
      final flags = Json.from(s.capsules[id] ?? {});
      if (d.state != 'capsule' ||
          !JournalVisibility.readable(d, flags, clock()) ||
          flags['openedAt'] != null) {
        return null;
      }
      flags.putIfAbsent('releasedAt', () => clock().toUtc().toIso8601String());
      flags['openedAt'] = clock().toUtc().toIso8601String();
      s.capsules[id] = flags;
      final count = (s.meta['capsulesOpened'] as int? ?? 0) + 1;
      s.meta['capsulesOpened'] = count;
      final event = BusinessEvent('opened:$id', 'capsule-opened', clock(), {
        'journal': id,
        'count': count,
      });
      s.events[event.id] = event.toJson();
      return event;
    });
    notifyListeners();
    return event;
  }

  Future<List<String>> takeDueHint() async => state.transaction((s) {
    final today = naturalDay(clock());
    if (s.meta['dueHintDay'] == today) return <String>[];
    final due = <String>[
      for (final item in s.capsules.entries)
        if (item.value['releasedAt'] != null &&
            item.value['openedAt'] == null &&
            item.value['hintedAt'] == null)
          item.key,
    ];
    if (due.isNotEmpty) {
      s.meta['dueHintDay'] = today;
      for (final id in due) {
        s.capsules[id]['hintedAt'] = clock().toUtc().toIso8601String();
      }
    }
    return due;
  });
  List<Diary> get nearestNotifications =>
      entries.where((d) => d.state == 'capsule' && !readable(d)).toList()
        ..sort((a, b) => a.unlockAt!.compareTo(b.unlockAt!));

  Future<BusinessEvent> importGallery(
    String id,
    String path, {
    String description = '',
  }) async {
    final event = BusinessEvent('gallery:$id', 'gallery-imported', clock(), {
      'photo': id,
    });
    await state.transaction((s) {
      if (s.gallery.containsKey(id)) return;
      s.gallery[id] = {
        'id': id,
        'path': path,
        'description': description,
        'imported': clock().toIso8601String(),
      };
      s.media[path] = {'path': path, 'kind': 'image'};
      s.meta['galleryImported'] = (s.meta['galleryImported'] as int? ?? 0) + 1;
      s.events[event.id] = BusinessEvent(event.id, event.kind, event.at, {
        'count': s.meta['galleryImported'],
      }).toJson();
    });
    notifyListeners();
    return event;
  }
}
