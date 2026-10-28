import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../src/store.dart';
import 'model.dart';
import 'persistence.dart';

abstract class BackupFiles {
  Future<Uint8List> read(String path);
  String stagedPath(String session, String name);
  Future<String> stage(String session, String name, Uint8List bytes);
  String destination(String session, String name, Uint8List bytes);
  Future<void> promote(String staged, String destination);
  Future<void> remove(String path);
}

class MemoryBackupFiles extends BackupFiles {
  final Map<String, Uint8List> files = {};
  int? failPromotion;
  int promotions = 0;
  @override
  Future<Uint8List> read(String path) async =>
      files[path] ?? (throw StateError('附件缺失'));
  @override
  Future<String> stage(String session, String name, Uint8List bytes) async {
    final path = stagedPath(session, name);
    files[path] = bytes;
    return path;
  }

  @override
  String stagedPath(String session, String name) => 'staging/$session/$name';
  @override
  String destination(String session, String name, Uint8List bytes) =>
      'restored/$session/$name';
  @override
  Future<void> promote(String staged, String destination) async {
    promotions++;
    if (promotions == failPromotion) throw StateError('模拟中断');
    files[destination] = files.remove(staged)!;
  }

  @override
  Future<void> remove(String path) async {
    files.remove(path);
  }
}

class ImportPlan {
  final String session, baseline;
  final JournalState imported;
  final Map<String, String> idMap;
  final Map<String, Uint8List> media;
  final Set<String> skips;
  final Set<String> gallerySkips;
  final Set<String> resourceReplacements;
  ImportPlan(
    this.session,
    this.baseline,
    this.imported,
    this.idMap,
    this.media,
    this.skips,
    this.gallerySkips,
    this.resourceReplacements,
  );
  int get duplicates => skips.length;
  int get conflicts => idMap.entries.where((e) => e.key != e.value).length;
  int get additions => imported.entries.length - skips.length;
}

class BackupService {
  final AtomicState state;
  final BackupFiles files;
  final DateTime Function() clock;
  BackupService(this.state, this.files, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  static const maxBytes = 512 * 1024 * 1024, maxFiles = 20000;
  Future<Uint8List> export() async {
    final copy = state.snapshot;
    copy.meta.remove(
      'legacyOriginal',
    ); // original migration copy remains local.
    copy.meta.remove('importSession');
    final paths = <String>{
      for (final j in copy.entries.values) ...[
        ...List<String>.from(j['photos'] ?? []),
        if (j['audio'] != null) j['audio'] as String,
      ],
      for (final j in copy.gallery.values) j['path'] as String,
      for (final j in copy.resources.values)
        if (j['used'] == true && j['path'] != null) j['path'] as String,
    };
    final blobs = <String, Uint8List>{};
    final mapping = <String, String>{};
    var total = 0;
    for (final path in paths) {
      final name = 'media/${blobs.length.toString().padLeft(6, '0')}';
      blobs[name] = await files.read(path);
      total += blobs[name]!.length;
      if (total > maxBytes) throw const FormatException('备份超过当前容量限制');
      mapping[path] = name;
    }
    copy.media.removeWhere((key, value) => !paths.contains(key));
    for (final r in copy.resources.values) {
      if (r['used'] != true) {
        r.remove('path');
        r['available'] = false;
      }
    }
    _mapMedia(copy, mapping);
    final manifest = {
      'format': 'shike',
      'version': 2,
      'created': clock().toUtc().toIso8601String(),
      'state': copy.toJson(),
      'files': {
        for (final e in blobs.entries)
          e.key: {'length': e.value.length, 'crc32': getCrc32(e.value)},
      },
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    if (total + manifestBytes.length > maxBytes) {
      throw const FormatException('备份超过当前容量限制');
    }
    final archive = Archive()
      ..addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );
    for (final e in blobs.entries) {
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    return bytes;
  }

  Future<void> markExported() => state.transaction(
    (s) => s.meta['lastBackup'] = clock().toIso8601String(),
  );

  Future<ImportPlan> prepareImport(Uint8List bytes) async {
    if (bytes.length > maxBytes) throw const FormatException('备份过大');
    final Json manifest;
    final media = <String, Uint8List>{};
    if (bytes.isNotEmpty && bytes[0] == 0x50) {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      if (archive.length > maxFiles) throw const FormatException('文件过多');
      var total = 0;
      final names = <String>{};
      for (final f in archive) {
        if (!f.isFile || !_safePath(f.name) || !names.add(f.name)) {
          throw const FormatException('备份路径无效');
        }
        total += f.size;
        if (total > maxBytes) throw const FormatException('备份解压后过大');
        final content = Uint8List.fromList(f.content);
        if (content.length != f.size) throw const FormatException('备份长度不符');
        media[f.name] = content;
      }
      final raw = media.remove('manifest.json');
      if (raw == null) throw const FormatException('备份目录缺失');
      manifest = Json.from(jsonDecode(utf8.decode(raw)));
    } else {
      final legacy = Json.from(jsonDecode(utf8.decode(bytes)));
      manifest = _legacy(legacy, media);
    }
    if (manifest['format'] != 'shike' || manifest['version'] != 2) {
      throw const FormatException('不支持的备份版本');
    }
    final metadata = Json.from(manifest['files'] ?? {});
    if (metadata.length != media.length) throw const FormatException('附件数量不符');
    for (final item in metadata.entries) {
      final content = media[item.key];
      if (content == null ||
          content.length != item.value['length'] ||
          getCrc32(content) != item.value['crc32']) {
        throw const FormatException('附件损坏');
      }
    }
    final incoming = JournalState.fromJson(Json.from(manifest['state']));
    _validate(incoming, media.keys.toSet());
    final current = state.snapshot,
        ids = <String, String>{},
        skips = <String>{},
        gallerySkips = <String>{};
    for (final item in incoming.entries.entries) {
      final existing = current.entries[item.key];
      if (existing == null) {
        ids[item.key] = item.key;
      } else if (await _sameEntry(current, incoming, item.key, media)) {
        ids[item.key] = item.key;
        skips.add(item.key);
      } else {
        ids[item.key] = const Uuid().v4();
      }
    }
    for (final item in incoming.gallery.entries) {
      final old = current.gallery[item.key];
      if (old == null) continue;
      final a = Json.from(old)..remove('path'),
          b = Json.from(item.value)..remove('path');
      try {
        if (jsonEncode(a) == jsonEncode(b) &&
            listEquals(
              await files.read(old['path']),
              media[item.value['path']],
            )) {
          gallerySkips.add(item.key);
        }
      } catch (_) {}
    }
    final needed = <String>{
      for (final e in incoming.entries.entries)
        if (!skips.contains(e.key)) ...[
          ...List<String>.from(e.value['photos'] ?? []),
          if (e.value['audio'] != null) e.value['audio'] as String,
        ],
      for (final e in incoming.gallery.entries)
        if (!gallerySkips.contains(e.key)) e.value['path'] as String,
    };
    final resourceReplacements = <String>{};
    for (final r in incoming.resources.entries) {
      if (r.value['used'] != true || r.value['path'] == null) continue;
      final old = current.resources[r.key];
      var available = false;
      if (old?['path'] != null) {
        try {
          await files.read(old['path']);
          available = true;
        } catch (_) {}
      }
      if (!available) {
        needed.add(r.value['path']);
        resourceReplacements.add(r.key);
      }
    }
    media.removeWhere((key, value) => !needed.contains(key));
    incoming.media.removeWhere((key, value) => !needed.contains(key));
    return ImportPlan(
      const Uuid().v4(),
      jsonEncode(current.toJson()),
      incoming,
      ids,
      media,
      skips,
      gallerySkips,
      resourceReplacements,
    );
  }

  Future<void> applyImport(ImportPlan plan) async {
    if (jsonEncode(state.snapshot.toJson()) != plan.baseline) {
      throw StateError('记录有变化，请重新预览备份');
    }
    final staged = <String, String>{}, destinations = <String, String>{};
    try {
      for (final item in plan.media.entries) {
        final name = item.key.split('/').last;
        staged[item.key] = files.stagedPath(plan.session, name);
        destinations[item.key] = files.destination(
          plan.session,
          name,
          item.value,
        );
      }
      await state.transaction((s) {
        if (jsonEncode(s.toJson()) != plan.baseline) {
          throw StateError('记录有变化，请重新预览备份');
        }
        s.meta['importSession'] = {
          'id': plan.session,
          'staged': staged.values.toList(),
          'destinations': destinations.values.toList(),
        };
      });
      for (final item in plan.media.entries) {
        await files.stage(plan.session, item.key.split('/').last, item.value);
      }
      for (final item in staged.entries) {
        await files.promote(item.value, destinations[item.key]!);
      }
      await state.transaction((s) {
        if (s.meta['importSession']?['id'] != plan.session) {
          throw StateError('恢复状态不符');
        }
        final current = s.copy()..meta.remove('importSession');
        if (jsonEncode(current.toJson()) != plan.baseline) {
          throw StateError('恢复期间记录有变化，请重新预览备份');
        }
        final incoming = plan.imported.copy();
        _mapMedia(incoming, destinations);
        final wasEmpty = s.entries.isEmpty && s.gallery.isEmpty;
        for (final item in incoming.entries.entries) {
          if (plan.skips.contains(item.key)) {
            final old = Json.from(s.capsules[item.key] ?? {}),
                incomingFlags = Json.from(incoming.capsules[item.key] ?? {});
            for (final key in ['releasedAt', 'openedAt', 'hintedAt']) {
              if (old[key] == null && incomingFlags[key] != null) {
                old[key] = incomingFlags[key];
              }
            }
            if (old.isNotEmpty) s.capsules[item.key] = old;
            continue;
          }
          final id = plan.idMap[item.key]!;
          s.entries[id] = {...Json.from(item.value), 'id': id};
          if (id != item.key) {
            s.meta['origin:$id'] = {'id': item.key, 'session': plan.session};
          }
          s.links[id] = [
            for (final r in incoming.links[item.key] ?? [])
              SentenceLink.fromJson(Json.from(r)).remap(plan.idMap).toJson(),
          ];
          if (incoming.snapshots.containsKey(item.key)) {
            s.snapshots[id] = incoming.snapshots[item.key];
          }
          if (incoming.drafts.containsKey(item.key)) {
            s.drafts[id] = incoming.drafts[item.key];
          }
          if (incoming.capsules.containsKey(item.key)) {
            s.capsules[id] = incoming.capsules[item.key];
          }
        }
        for (final item in incoming.gallery.entries) {
          if (plan.gallerySkips.contains(item.key)) continue;
          if (s.gallery[item.key] == null) {
            s.gallery[item.key] = item.value;
          } else if (jsonEncode(s.gallery[item.key]) !=
              jsonEncode(item.value)) {
            final id = const Uuid().v4();
            s.gallery[id] = {...Json.from(item.value), 'id': id};
          }
        }
        for (final item in incoming.grants.entries) {
          s.grants.putIfAbsent(item.key, () => item.value);
        }
        for (final item in incoming.resources.entries) {
          final old = Json.from(s.resources[item.key] ?? {});
          s.resources[item.key] = {
            ...Json.from(item.value),
            ...old,
            if (plan.resourceReplacements.contains(item.key))
              'path': item.value['path'],
            'used': old['used'] == true || item.value['used'] == true,
          };
        }
        s.media.addAll(incoming.media);
        final attempts = Json.from(incoming.meta['rewardAttempts'] ?? {})
          ..addAll(Json.from(s.meta['rewardAttempts'] ?? {}));
        s.meta['rewardAttempts'] = attempts;
        final weeks = Json.from(incoming.meta['rememberedWeeks'] ?? {})
          ..addAll(Json.from(s.meta['rememberedWeeks'] ?? {}));
        for (final raw in [incoming.meta['randomWeek'], s.meta['randomWeek']]) {
          final key = normalizedWeek(raw);
          if (key != null) weeks.putIfAbsent(key, () => true);
        }
        s.meta['rememberedWeeks'] = weeks;
        for (final key in ['galleryImported', 'capsulesOpened']) {
          final old = s.meta[key] as int? ?? 0,
              restored = incoming.meta[key] as int? ?? 0;
          s.meta[key] = old > restored ? old : restored;
        }
        final actualOpened = s.capsules.values
            .where((c) => c['openedAt'] != null)
            .length;
        if (actualOpened > (s.meta['capsulesOpened'] as int? ?? 0)) {
          s.meta['capsulesOpened'] = actualOpened;
        }
        if (wasEmpty) {
          s.settings
            ..clear()
            ..addAll(incoming.settings);
        }
        s.meta['lastImport'] = clock().toIso8601String();
        s.meta.remove('importSession');
        // Imported records never become fresh reward events.
      });
    } catch (_) {
      for (final file in [...staged.values, ...destinations.values]) {
        await files.remove(file);
      }
      await state.transaction((s) {
        if (s.meta['importSession']?['id'] == plan.session) {
          s.meta.remove('importSession');
        }
      });
      rethrow;
    }
  }

  Future<void> recoverInterruptedImport() async {
    final pending = state.snapshot.meta['importSession'];
    if (pending == null) return;
    for (final path in [...pending['staged'], ...pending['destinations']]) {
      await files.remove(path);
    }
    await state.transaction((s) => s.meta.remove('importSession'));
  }

  static bool _safePath(String path) =>
      !path.startsWith('/') &&
      !path.contains('\\') &&
      !path.contains(':') &&
      !path.split('/').contains('..');
  Future<bool> _sameEntry(
    JournalState a,
    JournalState b,
    String id,
    Map<String, Uint8List> media,
  ) async {
    final left = cloneJson(Json.from(a.entries[id])),
        right = cloneJson(Json.from(b.entries[id]));
    final oldPaths = [
      ...List<String>.from(left.remove('photos') ?? []),
      if (left['audio'] != null) left['audio'] as String,
    ];
    final newPaths = [
      ...List<String>.from(right.remove('photos') ?? []),
      if (right['audio'] != null) right['audio'] as String,
    ];
    final hasAudio = left.remove('audio') != null,
        otherAudio = right.remove('audio') != null;
    if (hasAudio != otherAudio ||
        oldPaths.length != newPaths.length ||
        jsonEncode(left) != jsonEncode(right) ||
        jsonEncode(a.links[id] ?? []) != jsonEncode(b.links[id] ?? []) ||
        jsonEncode(a.snapshots[id]) != jsonEncode(b.snapshots[id])) {
      return false;
    }
    for (var i = 0; i < oldPaths.length; i++) {
      try {
        if (!listEquals(await files.read(oldPaths[i]), media[newPaths[i]])) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  static void _validate(JournalState s, Set<String> media) {
    for (final item in s.entries.entries) {
      final d = Diary.fromJson(Json.from(item.value));
      if (d.id != item.key ||
          !['draft', 'done', 'capsule'].contains(d.state) ||
          d.mood != null && (d.mood! < 0 || d.mood! > 5) ||
          d.state == 'capsule' && d.unlockAt == null) {
        throw const FormatException('日记字段无效');
      }
      final links = [
        for (final j in s.links[d.id] ?? [])
          SentenceLink.fromJson(Json.from(j)),
      ];
      LinkEditing.validate(d.id, d.text, links);
      for (final r in links) {
        if (!s.entries.containsKey(r.target)) {
          throw const FormatException('引用目标缺失');
        }
      }
      for (final file in [...d.photos, if (d.audio != null) d.audio!]) {
        if (!media.contains(file)) throw const FormatException('附件缺失');
      }
    }
    for (final photo in s.gallery.values) {
      if (!media.contains(photo['path'])) throw const FormatException('拾影附件缺失');
    }
    for (final resource in s.resources.values) {
      if (resource['used'] == true &&
          resource['path'] != null &&
          !media.contains(resource['path'])) {
        throw const FormatException('卡片照片缺失');
      }
    }
  }

  static void _mapMedia(JournalState s, Map<String, String> paths) {
    for (final j in s.entries.values) {
      j['photos'] = [for (final path in j['photos'] ?? []) paths[path] ?? path];
      if (j['audio'] != null) j['audio'] = paths[j['audio']] ?? j['audio'];
    }
    for (final j in s.gallery.values) {
      j['path'] = paths[j['path']] ?? j['path'];
    }
    for (final j in s.resources.values) {
      if (j['path'] != null) j['path'] = paths[j['path']] ?? j['path'];
    }
    final registered = {
      for (final item in s.media.entries)
        paths[item.key] ?? item.key: {
          ...Json.from(item.value),
          'path': paths[item.key] ?? item.key,
        },
    };
    s.media
      ..clear()
      ..addAll(registered);
  }

  static Json _legacy(Json old, Map<String, Uint8List> media) {
    if (!['shike', 'shike-backup'].contains(old['format']) ||
        old['version'] != 1) {
      throw const FormatException('不支持的备份');
    }
    final s = JournalState();
    String? decode(dynamic value) {
      if (value == null) return null;
      final name = 'media/${media.length}';
      media[name] = base64Decode(value as String);
      return name;
    }

    for (final raw in old['entries'] as List? ?? []) {
      final j = Json.from(raw);
      j['photos'] = [for (final b in j['photos'] ?? []) decode(b)];
      j['audio'] = decode(j['audio']);
      s.entries[j['id']] = j;
    }
    for (final raw in old['gallery'] as List? ?? []) {
      final j = Json.from(raw);
      final id = j['id'] ?? const Uuid().v4();
      j['id'] = id;
      j['path'] = decode(j['data'] ?? j['image']);
      s.gallery[id] = j;
    }
    s.settings.addAll(Json.from(old['settings'] ?? {}));
    s.snapshots.addAll(Json.from(old['snapshots'] ?? {}));
    for (final item in Json.from(old['references'] ?? {}).entries) {
      s.links[item.key] = [
        for (final r in item.value)
          SentenceLink(
            id: const Uuid().v4(),
            source: item.key,
            target: r['target'],
            quote: r['text'],
            start: r['start'],
            end: r['end'],
          ).toJson(),
      ];
    }
    for (final c in old['cards'] ?? []) {
      s.grants[c['key']] = c;
    }
    s.meta['galleryImported'] = s.gallery.length;
    s.meta['randomWeek'] = normalizedWeek(old['randomWeek']);
    return {
      'format': 'shike',
      'version': 2,
      'state': s.toJson(),
      'files': {
        for (final item in media.entries)
          item.key: {
            'length': item.value.length,
            'crc32': getCrc32(item.value),
          },
      },
    };
  }
}
