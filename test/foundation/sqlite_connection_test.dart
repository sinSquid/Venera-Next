import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/foundation/sqlite_connection.dart';

void _initializeDatabase(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('CREATE TABLE items (id INTEGER PRIMARY KEY, value TEXT);');
    db.execute("INSERT INTO items (value) VALUES ('seed');");
  } finally {
    db.dispose();
  }
}

bool _sqliteAvailable() {
  try {
    final db = sqlite3.openInMemory();
    db.dispose();
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _holdTemporaryWriteLock(
  (String, SendPort, SendPort) arguments,
) async {
  final (path, ready, completed) = arguments;
  final release = ReceivePort();
  Database? db;
  String? failure;
  try {
    db = sqlite3.open(path);
    db.execute('BEGIN EXCLUSIVE;');
    db.execute("INSERT INTO items (value) VALUES ('released');");
    ready.send(release.sendPort);
    await release.first;
    // This timer must run in another isolate: opening the second SQLite
    // connection synchronously blocks the test isolate until the lock clears.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    db.execute('COMMIT;');
  } catch (error) {
    failure = error.toString();
    ready.send(failure);
  } finally {
    db?.dispose();
    release.close();
    completed.send(failure);
  }
}

void main() {
  final sqliteAvailable = _sqliteAvailable();

  test('failed PRAGMA setup releases a corrupt database file', () {
    final dir = Directory.systemTemp.createTempSync('sqlite-corrupt-');
    try {
      final path = '${dir.path}/corrupt.db';
      File(path).writeAsBytesSync(List.filled(4096, 42));
      expect(() => openSqliteDatabase(path), throwsA(isA<SqliteException>()));
      File(path).renameSync('$path.failed');
      _initializeDatabase(path);
      final db = openSqliteDatabase(path);
      try {
        expect(db.select('SELECT value FROM items;').single['value'], 'seed');
      } finally {
        db.dispose();
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  }, skip: !sqliteAvailable);

  test(
    'openSqliteDatabase sets DELETE journal mode, NORMAL synchronous, and busy_timeout',
    () {
      final dir = Directory.systemTemp.createTempSync('venera-sqlite-helper-');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final db = openSqliteDatabase('${dir.path}/helper.db');
      addTearDown(db.dispose);

      final journalMode = db
          .select('PRAGMA journal_mode;')
          .first['journal_mode'];
      final synchronous = db.select('PRAGMA synchronous;').first['synchronous'];
      final busyTimeout = db.select('PRAGMA busy_timeout;').first['timeout'];

      expect((journalMode as String).toLowerCase(), 'delete');
      expect(synchronous, 1);
      expect(busyTimeout, 5000);
    },
    skip: sqliteAvailable ? false : 'sqlite3 native library is unavailable',
  );

  test(
    'withDatabase opens, executes, and disposes',
    () async {
      final dir = Directory.systemTemp.createTempSync('venera-sqlite-withdb-');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final dbPath = '${dir.path}/test.db';
      _initializeDatabase(dbPath);

      final count = await withDatabase<int>(dbPath, (db) async {
        final res = db
            .select('SELECT count(*) AS count FROM items;')
            .first['count'];
        return res as int;
      });

      expect(count, 1);
    },
    skip: sqliteAvailable ? false : 'sqlite3 native library is unavailable',
  );

  test(
    'openSqliteDatabase waits for a short lock during PRAGMA setup',
    () async {
      final dir = Directory.systemTemp.createTempSync('venera-sqlite-open-');
      final dbPath = '${dir.path}/lock.db';
      _initializeDatabase(dbPath);
      final ready = ReceivePort();
      final completed = ReceivePort();
      final completion = completed.first;
      final worker = await Isolate.spawn(_holdTemporaryWriteLock, (
        dbPath,
        ready.sendPort,
        completed.sendPort,
      ));
      try {
        final release = await ready.first.timeout(const Duration(seconds: 5));
        expect(release, isA<SendPort>());
        (release as SendPort).send(null);

        final db = openSqliteDatabase(dbPath);
        try {
          expect(
            db
                .select('SELECT value FROM items ORDER BY id;')
                .map((r) => r['value']),
            ['seed', 'released'],
          );
        } finally {
          db.dispose();
        }
      } finally {
        try {
          expect(await completion.timeout(const Duration(seconds: 5)), isNull);
        } finally {
          worker.kill(priority: Isolate.immediate);
          ready.close();
          completed.close();
          dir.deleteSync(recursive: true);
        }
      }
    },
    skip: sqliteAvailable ? false : 'sqlite3 native library is unavailable',
  );

  test(
    'plain sqlite3 connections hit a read-then-write lock on the same file',
    () {
      final dir = Directory.systemTemp.createTempSync('venera-sqlite-lock-');
      addTearDown(() {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final dbPath = '${dir.path}/lock.db';
      _initializeDatabase(dbPath);

      final reader = sqlite3.open(dbPath);
      final writer = sqlite3.open(dbPath);
      addTearDown(reader.dispose);
      addTearDown(writer.dispose);

      reader.execute('BEGIN;');
      reader.select('SELECT * FROM items;');

      expect(
        () => writer.execute("INSERT INTO items (value) VALUES ('locked');"),
        throwsA(
          isA<SqliteException>().having(
            (error) => error.resultCode,
            'resultCode',
            5,
          ),
        ),
      );
    },
    skip: sqliteAvailable ? false : 'sqlite3 native library is unavailable',
  );
}
