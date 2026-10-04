import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/foundation/cache_scan.dart';

({CacheManager manager, Directory root}) fixture({
  CacheScanner scanner = scanCacheDirectory,
}) {
  final root = Directory.systemTemp.createTempSync('venera-cache-');
  final manager = CacheManager.open(
    dataPath: root.path,
    cacheRoot: root.path,
    scanner: scanner,
  );
  addTearDown(() async {
    await manager.dispose();
    await root.delete(recursive: true);
  });
  return (manager: manager, root: root);
}

void main() {
  test('queued image writes retain independent byte snapshots', () async {
    final gate = Completer<CacheScanResult>();
    final f = fixture(scanner: (_, _) => gate.future);
    final scanning = f.manager.start();
    final image = Uint8List.fromList([0, 1, 127, 128, 255]);
    final write = f.manager.writeCache('image', image);
    image.fillRange(0, image.length, 42);
    gate.complete(const CacheScanResult(0, []));
    await Future.wait([scanning, write]);

    expect(await (await f.manager.findCache('image'))!.readAsBytes(), [
      0,
      1,
      127,
      128,
      255,
    ]);
    expect(f.manager.currentSize, 5);
  });

  test('legacy caches use indexed cleanup and retain the newest data', () async {
    final root = Directory.systemTemp.createTempSync('venera-legacy-cache-');
    final db = sqlite3.open('${root.path}/cache.db');
    db.execute('''
      CREATE TABLE cache (
        key TEXT PRIMARY KEY NOT NULL,
        dir TEXT NOT NULL,
        name TEXT NOT NULL,
        expires INTEGER NOT NULL,
        type TEXT
      )
    ''');
    final expires = DateTime.now().millisecondsSinceEpoch + 86400000;
    for (var i = 0; i < 3; i++) {
      final file = File('${root.path}/cache/0/image$i');
      file.createSync(recursive: true);
      file.writeAsBytesSync(Uint8List(600 * 1024));
      db.execute('INSERT INTO cache VALUES (?, ?, ?, ?, NULL)', [
        'image$i',
        '0',
        'image$i',
        expires + i,
      ]);
    }
    db.dispose();
    final manager = CacheManager.open(
      dataPath: root.path,
      cacheRoot: root.path,
    );
    final inspector = sqlite3.open('${root.path}/cache.db');
    addTearDown(() async {
      await manager.dispose();
      inspector.dispose();
      await root.delete(recursive: true);
    });

    // Guard the query cost on large existing caches without timing assertions.
    final oldestPlan = inspector
        .select(
          'EXPLAIN QUERY PLAN SELECT * FROM cache ORDER BY expires ASC LIMIT 10',
        )
        .map((row) => row['detail'])
        .join(' ');
    final ownershipPlan = inspector
        .select(
          'EXPLAIN QUERY PLAN SELECT key FROM cache WHERE dir = ? AND name = ?',
          ['0', 'image0'],
        )
        .map((row) => row['detail'])
        .join(' ');
    expect(oldestPlan, isNot(contains('USE TEMP B-TREE')));
    expect(ownershipPlan, contains(RegExp(r'USING (COVERING )?INDEX')));

    await manager.start();
    expect(manager.currentSize, 1800 * 1024);
    manager.setLimitSize(1);
    await manager.checkCache();
    expect(await manager.findCache('image0'), isNull);
    expect(await manager.findCache('image1'), isNull);
    expect(await manager.findCache('image2'), isNotNull);
    expect(manager.currentSize, 600 * 1024);
  });

  test('construction does not scan and start shares one scan', () async {
    var scans = 0;
    final gate = Completer<CacheScanResult>();
    final f = fixture(
      scanner: (_, _) {
        scans++;
        return gate.future;
      },
    );
    expect(scans, 0);
    final first = f.manager.start();
    expect(identical(first, f.manager.start()), isTrue);
    await pumpEventQueue();
    expect(scans, 1);
    gate.complete(const CacheScanResult(0, []));
    await first;
  });

  test('scan failure keeps later writes usable', () async {
    final f = fixture(scanner: (_, _) async => throw StateError('scan failed'));
    await f.manager.start();
    await f.manager.writeCache('key', [1, 2, 3]);
    expect(f.manager.currentSize, 3);
    expect(await (await f.manager.findCache('key'))!.readAsBytes(), [1, 2, 3]);
  });

  test(
    'queued clear follows scan and write without restoring stale size',
    () async {
      final gate = Completer<CacheScanResult>();
      final f = fixture(scanner: (_, _) => gate.future);
      final scanning = f.manager.start();
      final bytes = [1, 2, 3];
      final write = f.manager.writeCache('key', bytes);
      bytes[0] = 9;
      final clear = f.manager.clear();
      gate.complete(const CacheScanResult(0, []));
      await Future.wait([scanning, write, clear]);
      expect(f.manager.currentSize, 0);
      expect(await f.manager.findCache('key'), isNull);
    },
  );

  test('dispose drains accepted writes and rejects new work', () async {
    final gate = Completer<CacheScanResult>();
    final f = fixture(scanner: (_, _) => gate.future);
    final scanning = f.manager.start();
    final write = f.manager.writeCache('key', [1, 2]);
    final closing = f.manager.dispose();
    expect(identical(closing, f.manager.dispose()), isTrue);
    await expectLater(f.manager.writeCache('late', [3]), throwsStateError);
    gate.complete(const CacheScanResult(0, []));
    await Future.wait([scanning, write, closing]);
    final reopened = CacheManager.open(
      dataPath: f.root.path,
      cacheRoot: f.root.path,
    );
    try {
      await reopened.start();
      expect(await (await reopened.findCache('key'))!.readAsBytes(), [1, 2]);
      expect(reopened.currentSize, 2);
    } finally {
      await reopened.dispose();
    }
  });

  test('failed file write does not poison queued operations', () async {
    final f = fixture();
    final cache = Directory('${f.root.path}/cache');
    await cache.delete();
    final obstruction = File(cache.path)..writeAsStringSync('blocked');
    await expectLater(
      f.manager.writeCache('key', [1]),
      throwsA(isA<FileSystemException>()),
    );
    await obstruction.delete();
    await cache.create();
    await f.manager.writeCache('key', [1]);
    expect(await (await f.manager.findCache('key'))!.readAsBytes(), [1]);
  });

  test(
    'real scan removes unmanaged files and preserves tracked data',
    () async {
      final f = fixture();
      await f.manager.writeCache('key', [1, 2, 3]);
      final unmanaged = File('${f.root.path}/cache/orphan')
        ..writeAsStringSync('unused');
      await f.manager.start();
      expect(await unmanaged.exists(), isFalse);
      expect(f.manager.currentSize, 3);
      expect(await (await f.manager.findCache('key'))!.readAsBytes(), [
        1,
        2,
        3,
      ]);
    },
  );

  test('owned cache paths and size limits are independent', () async {
    final first = fixture();
    final second = fixture();
    await first.manager.writeCache('same', [1]);
    await second.manager.writeCache('same', [2, 3]);
    first.manager.setLimitSize(0);
    await first.manager.checkCache();
    expect(await first.manager.findCache('same'), isNull);
    expect(first.manager.currentSize, 0);
    expect(await (await second.manager.findCache('same'))!.readAsBytes(), [
      2,
      3,
    ]);
  });

  test('expired lookups release size without evicting live entries', () async {
    final f = fixture();
    final bytes = List<int>.filled(600 * 1024, 1);
    await f.manager.writeCache('expired', bytes, -1);
    await f.manager.writeCache('live', bytes);

    expect(await f.manager.findCache('expired'), isNull);
    expect(f.manager.currentSize, bytes.length);
    f.manager.setLimitSize(1);
    await f.manager.checkCacheIfRequired();

    expect(await f.manager.findCache('live'), isNotNull);
    expect(f.manager.currentSize, bytes.length);
  });

  test('cleanup resets size after tracked files disappear', () async {
    final f = fixture();
    await f.manager.writeCache('missing', [1, 2, 3]);
    final file = (await f.manager.findCache('missing'))!;
    await file.delete();

    f.manager.setLimitSize(0);
    await f.manager.checkCache();

    expect(f.manager.currentSize, 0);
    expect(await f.manager.findCache('missing'), isNull);
    f.manager.setLimitSize(1);
    await f.manager.writeCache('new', [4]);
    expect(f.manager.currentSize, 1);
    expect(await (await f.manager.findCache('new'))!.readAsBytes(), [4]);
  });

  test('scan matches ownership by directory as well as filename', () async {
    final f = fixture();
    await f.manager.writeCache('key', [1, 2, 3]);
    final managed = (await f.manager.findCache('key'))!;
    final name = managed.uri.pathSegments.last;
    final orphan = File('${f.root.path}/cache/orphan/$name');
    await orphan.create(recursive: true);
    await orphan.writeAsBytes([4, 5]);

    final result = await scanCacheDirectory(
      '${f.root.path}/cache.db',
      '${f.root.path}/cache',
    );

    expect(result.totalSize, 3);
    expect(result.unmanagedFiles, [orphan.path]);
  });
}
