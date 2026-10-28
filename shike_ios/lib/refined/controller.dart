import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../src/store.dart';
import '../src/rewards.dart' show RewardCard, Rewards;

String dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
DateTime localDay(DateTime d) => DateTime(d.year, d.month, d.day);
bool onDay(DateTime a, DateTime b) => dayKey(a) == dayKey(b);

class MoodDay {
  final DateTime date;
  final List<Diary> entries;
  MoodDay(this.date, Iterable<Diary> values)
    : entries = values.toList()..sort((a, b) => b.created.compareTo(a.created));
  double? get mean {
    final valid = entries.where((e) => e.mood != null).toList();
    return valid.isEmpty
        ? null
        : valid.fold<int>(0, (sum, e) => sum + e.mood!) / valid.length;
  }

  int? get lastMood => entries.isEmpty ? null : entries.first.mood;
}

class GalleryPhoto {
  final String id, path;
  final DateTime imported;
  String description;
  GalleryPhoto({
    required this.id,
    required this.path,
    required this.imported,
    this.description = '',
  });
  factory GalleryPhoto.fromJson(Map<String, dynamic> j, int index) =>
      GalleryPhoto(
        id: j['id'] as String? ?? 'legacy-$index',
        path: j['path'] as String,
        imported:
            DateTime.tryParse(j['imported'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(1000000 - index),
        description: j['description'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'description': description,
    'imported': imported.toIso8601String(),
  };
}

class JournalReference {
  final String target, text;
  final int start, end;
  const JournalReference({
    required this.target,
    required this.text,
    required this.start,
    required this.end,
  });
  Map<String, dynamic> toJson() => {
    'target': target,
    'text': text,
    'start': start,
    'end': end,
  };
  factory JournalReference.fromJson(Map<String, dynamic> j) => JournalReference(
    target: j['target'] as String,
    text: j['text'] as String,
    start: j['start'] as int,
    end: j['end'] as int,
  );
  bool fits(String value) =>
      start >= 0 &&
      end <= value.length &&
      end > start &&
      value.substring(start, end) == text;
}

class RefinedController extends ChangeNotifier {
  final ShikeStore store;
  final bool demo;
  final List<GalleryPhoto> photos = [];
  final List<RewardCard> cards = [];
  final Map<String, String> cardImages = {};
  final Map<String, String> snapshots = {};
  final Map<String, List<JournalReference>> references = {};
  final Map<String, dynamic> settings = {
    'greeting': false,
    'city': '',
    'weather': false,
    'exportMood': true,
  };
  SharedPreferences? prefs;
  RefinedController(this.store, {this.demo = false}) {
    store.addListener(_changed);
  }
  void _changed() => notifyListeners();
  Future<void> initialize() async {
    if (demo) return;
    prefs = await SharedPreferences.getInstance();
    final gallery =
        jsonDecode(prefs!.getString('gallery.items') ?? '[]') as List;
    photos.addAll(
      gallery.indexed.map(
        (x) => GalleryPhoto.fromJson(Map<String, dynamic>.from(x.$2), x.$1),
      ),
    );
    cards.addAll(await Rewards.load());
    final values =
        jsonDecode(prefs!.getString('refined.settings') ?? '{}') as Map;
    settings.addAll(Map<String, dynamic>.from(values));
    final links = Map<String, dynamic>.from(
      jsonDecode(prefs!.getString('refined.references') ?? '{}'),
    );
    for (final e in links.entries) {
      references[e.key] = (e.value as List)
          .map((x) => JournalReference.fromJson(Map<String, dynamic>.from(x)))
          .toList();
    }
    cardImages.addAll(
      Map<String, String>.from(
        jsonDecode(prefs!.getString('refined.cardImages') ?? '{}'),
      ),
    );
    snapshots.addAll(
      Map<String, String>.from(
        jsonDecode(prefs!.getString('refined.snapshots') ?? '{}'),
      ),
    );
  }

  List<Diary> get visible => store.completed;
  List<Diary> get timeline =>
      store.entries.where((e) => e.state != 'draft').toList()
        ..sort((a, b) => b.created.compareTo(a.created));
  List<Diary> dayEntries(DateTime date) =>
      visible.where((e) => onDay(e.created, date)).toList()
        ..sort((a, b) => b.created.compareTo(a.created));
  List<MoodDay> period(DateTime start, int count) => List.generate(count, (i) {
    final date = DateTime(start.year, start.month, start.day + i);
    return MoodDay(date, dayEntries(date));
  });
  Future<void> saveLinks(String id, List<JournalReference> links) async {
    references[id] = List.of(links);
    await prefs?.setString(
      'refined.references',
      jsonEncode(
        references.map(
          (key, value) => MapEntry(key, value.map((e) => e.toJson()).toList()),
        ),
      ),
    );
  }

  Future<List<RewardCard>> reward(Diary diary) async {
    if (demo || diary.state == 'capsule') return [];
    final added = await Rewards.evaluate(store, diary);
    cards
      ..clear()
      ..addAll(await Rewards.load());
    notifyListeners();
    return added;
  }

  Future<void> addPhoto(String path) async {
    photos.insert(
      0,
      GalleryPhoto(id: store.newId(), path: path, imported: DateTime.now()),
    );
    await savePhotos();
  }

  Future<void> savePhotos() async {
    await prefs?.setString(
      'gallery.items',
      jsonEncode(photos.map((e) => e.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> removePhoto(String id) async {
    photos.removeWhere((e) => e.id == id);
    await savePhotos();
  }

  Future<void> reloadCollections() async {
    if (demo) return;
    final gallery =
        jsonDecode(prefs!.getString('gallery.items') ?? '[]') as List;
    photos
      ..clear()
      ..addAll(
        gallery.indexed.map(
          (x) => GalleryPhoto.fromJson(Map<String, dynamic>.from(x.$2), x.$1),
        ),
      );
    cards
      ..clear()
      ..addAll(await Rewards.load());
    notifyListeners();
  }

  Future<void> setSetting(String key, dynamic value) async {
    settings[key] = value;
    await prefs?.setString('refined.settings', jsonEncode(settings));
    notifyListeners();
  }

  String metadata(DateTime date) => [
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
    if ((settings['city'] as String).isNotEmpty) settings['city'] as String,
  ].join(' · ');
  String savedMetadata(Diary d) =>
      snapshots[d.id] ??
      '${d.created.year}.${d.created.month.toString().padLeft(2, '0')}.${d.created.day.toString().padLeft(2, '0')}';
  Future<void> snapshot(String id, String value) async {
    snapshots.putIfAbsent(id, () => value);
    await prefs?.setString('refined.snapshots', jsonEncode(snapshots));
  }

  Future<String?> phrase(String group) async {
    final raw = await rootBundle.loadString('assets/phrases.json');
    final map = jsonDecode(raw.trimLeft().replaceFirst('\ufeff', '')) as Map;
    final all = List<String>.from(map[group] as List);
    final recent = prefs?.getStringList('refined.recent.$group') ?? [];
    final available = all.where((s) => !recent.contains(s)).toList();
    final chosen =
        (available.isEmpty ? all : available)[Random().nextInt(
          available.isEmpty ? all.length : available.length,
        )];
    await prefs?.setStringList(
      'refined.recent.$group',
      [chosen, ...recent].take(5).toList(),
    );
    return chosen;
  }

  Future<String?> periodFeedback({
    required bool month,
    required DateTime now,
  }) async {
    final start = month
        ? DateTime(now.year, now.month, 1)
        : DateTime(now.year, now.month, now.day - now.weekday + 1);
    final end = month
        ? DateTime(now.year, now.month + 1, 1)
        : DateTime(start.year, start.month, start.day + 7);
    final key = 'refined.feedback.${month ? 'month' : 'week'}.${dayKey(start)}';
    if (prefs?.getBool(key) == true) return null;
    final entries = visible
        .where((e) => !e.created.isBefore(start) && e.created.isBefore(end))
        .toList();
    if (entries.isEmpty) return null;
    final happy = entries.where((e) => (e.mood ?? 0) >= 3).length;
    final group = entries.length < (month ? 5 : 3)
        ? 'encourage'
        : happy * 2 < entries.length
        ? 'comfort'
        : happy * 2 > entries.length
        ? 'praise'
        : null;
    if (group == null) return null;
    final text = await phrase(group);
    await prefs?.setBool(key, true);
    return text;
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }
}

/// Test/demo store: never writes fixture content to the user's database.
class PreviewStore extends ShikeStore {
  @override
  Future<void> save(Diary value) async {
    final old = entries.where((e) => e.id == value.id).firstOrNull;
    if (old != null && old.state != 'draft') throw StateError('已完成的日记不可修改');
    entries.removeWhere((e) => e.id == value.id);
    entries.add(value);
    entries.sort((a, b) => b.created.compareTo(a.created));
    notifyListeners();
  }

  @override
  Future<void> deleteDraft(String id) async {
    entries.removeWhere((e) => e.id == id && e.state == 'draft');
    notifyListeners();
  }
}
