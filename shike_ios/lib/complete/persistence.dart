import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'model.dart';

abstract class StatePersistence {
  Future<JournalState> read();
  Future<void> write(JournalState state);
  Future<void> close() async {}
}

class MemoryPersistence extends StatePersistence {
  JournalState state = JournalState();
  bool failNextWrite = false;
  @override
  Future<JournalState> read() async => state.copy();
  @override
  Future<void> write(JournalState value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Simulated disk failure');
    }
    state = value.copy();
  }
}

class SqlitePersistence extends StatePersistence {
  final Database database;
  SqlitePersistence(this.database);
  static Future<SqlitePersistence> open() async => SqlitePersistence(
    await openDatabase(
      path.join(await getDatabasesPath(), 'shike_complete.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE collections (name TEXT PRIMARY KEY, data TEXT NOT NULL)',
        );
      },
    ),
  );
  @override
  Future<JournalState> read() async {
    final rows = await database.query('collections');
    return JournalState.fromJson({
      for (final row in rows)
        row['name'] as String: jsonDecode(row['data'] as String),
    });
  }

  @override
  Future<void> write(JournalState value) => database.transaction((txn) async {
    final batch = txn.batch();
    for (final item in value.toJson().entries) {
      batch.insert('collections', {
        'name': item.key,
        'data': jsonEncode(item.value),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  });
  @override
  Future<void> close() => database.close();
}

/// Browser preview uses one atomic value. iOS always uses SQLite.
class PreferencesPersistence extends StatePersistence {
  final SharedPreferences preferences;
  PreferencesPersistence(this.preferences);
  static const key = 'complete.state.v2';
  @override
  Future<JournalState> read() async => JournalState.fromJson(
    jsonDecode(preferences.getString(key) ?? '{}') as Json,
  );
  @override
  Future<void> write(JournalState value) async {
    if (!await preferences.setString(key, jsonEncode(value.toJson()))) {
      throw StateError('保存失败');
    }
  }
}

Future<StatePersistence> openPersistence() async => kIsWeb
    ? PreferencesPersistence(await SharedPreferences.getInstance())
    : await SqlitePersistence.open();

class AtomicState {
  final StatePersistence persistence;
  JournalState _state;
  final List<Future<void> Function()> _queue = [];
  bool _busy = false;
  AtomicState(this.persistence, this._state);
  static Future<AtomicState> open(StatePersistence persistence) async =>
      AtomicState(persistence, await persistence.read());
  JournalState get snapshot => _state.copy();
  Future<T> transaction<T>(FutureOr<T> Function(JournalState) action) {
    final result = Completer<T>();
    Future<void> run() async {
      final pending = _state.copy();
      try {
        final output = await action(pending);
        await persistence.write(pending);
        _state = pending;
        _advance();
        result.complete(output);
      } catch (e, st) {
        _advance();
        result.completeError(e, st);
      }
    }

    if (_busy) {
      _queue.add(run);
    } else {
      _busy = true;
      unawaited(run());
    }
    return result.future;
  }

  void _advance() {
    if (_queue.isEmpty) {
      _busy = false;
    } else {
      unawaited(_queue.removeAt(0)());
    }
  }
}
