import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class Diary {
  final String id;
  final String text;
  final int? mood;
  final DateTime created;
  final DateTime updated;
  final String state;
  final DateTime? unlockAt;
  final List<String> photos;
  final String? audio;
  final bool capsuleDraft;
  Diary({required this.id, required this.text, required this.mood, required this.created,
    required this.updated, required this.state, this.unlockAt, this.photos = const [], this.audio, this.capsuleDraft = false});
  bool get lockedCapsule => state == 'capsule' && unlockAt != null && DateTime.now().isBefore(unlockAt!);
  bool get visible => state != 'draft' && !lockedCapsule;
  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'mood': mood, 'created': created.toIso8601String(),
    'updated': updated.toIso8601String(), 'state': state, 'unlockAt': unlockAt?.toIso8601String(), 'photos': photos, 'audio': audio,'capsuleDraft':capsuleDraft};
  factory Diary.fromJson(Map<String, dynamic> j) => Diary(id:j['id'] as String, text:j['text'] as String,
    mood:j['mood'] as int?, created:DateTime.parse(j['created'] as String), updated:DateTime.parse(j['updated'] as String),
    state:j['state'] as String, unlockAt:j['unlockAt'] == null ? null : DateTime.parse(j['unlockAt'] as String),
    photos: List<String>.from(j['photos'] as List? ?? []), audio:j['audio'] as String?,capsuleDraft:j['capsuleDraft'] as bool? ?? false);
}

class ShikeStore extends ChangeNotifier {
  final List<Diary> entries = [];
  Database? _db;
  SharedPreferences? _prefs;
  static const _uuid = Uuid();
  String newId() => _uuid.v4();
  static Future<ShikeStore> openPreferences() async {
    final s = ShikeStore();
    s._prefs = await SharedPreferences.getInstance();
    final raw = s._prefs!.getString('shike.entries');
    if (raw != null) s.entries.addAll((jsonDecode(raw) as List).map((e) => Diary.fromJson(Map<String,dynamic>.from(e))));
    s._sort();
    return s;
  }
  static Future<ShikeStore> open() async {
    if (kIsWeb) return openPreferences();
    final s = ShikeStore();
    {
      s._db = await openDatabase(p.join(await getDatabasesPath(), 'shike.db'), version: 1,
        onCreate:(db,version) async { await db.execute('CREATE TABLE diaries (id TEXT PRIMARY KEY, data TEXT NOT NULL)'); });
      final rows = await s._db!.query('diaries');
      s.entries.addAll(rows.map((e) => Diary.fromJson(jsonDecode(e['data'] as String))));
    }
    s._sort();
    return s;
  }
  void _sort() => entries.sort((a,b) => b.created.compareTo(a.created));
  List<Diary> get drafts => entries.where((e) => e.state == 'draft').toList();
  List<Diary> get completed => entries.where((e) => e.visible).toList();
  Future<void> save(Diary value) async {
    final old = entries.where((e) => e.id == value.id).firstOrNull;
    if (old != null && old.state != 'draft') throw StateError('已完成的日记不可修改');
    if (_db != null) {
      await _db!.insert('diaries', {'id':value.id, 'data':jsonEncode(value.toJson())}, conflictAlgorithm:ConflictAlgorithm.replace);
    } else {
      final copy = entries.where((e) => e.id != value.id).toList()..add(value);
      await _prefs!.setString('shike.entries',jsonEncode(copy.map((e) => e.toJson()).toList()));
    }
    entries.removeWhere((e) => e.id == value.id);
    entries.add(value); _sort(); notifyListeners();
  }
  Future<void> deleteDraft(String id) async {
    final old = entries.where((e) => e.id == id).firstOrNull;
    if (old == null || old.state != 'draft') return;
    if (_db != null) { await _db!.delete('diaries', where:'id = ?',whereArgs:[id]); }
    else { await _prefs!.setString('shike.entries',jsonEncode(entries.where((e) => e.id != id).map((e) => e.toJson()).toList())); }
    entries.removeWhere((e) => e.id == id); notifyListeners();
  }
}
