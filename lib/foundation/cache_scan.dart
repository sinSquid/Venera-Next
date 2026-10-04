import 'dart:isolate';
import 'dart:io';

import 'sqlite_connection.dart';

class CacheScanResult {
  const CacheScanResult(this.totalSize, this.unmanagedFiles);
  final int totalSize;
  final List<String> unmanagedFiles;
}

typedef CacheScanner =
    Future<CacheScanResult> Function(String dbPath, String directory);

Future<CacheScanResult> scanCacheDirectory(String dbPath, String dir) async {
  return Isolate.run(() async {
    int totalSize = 0;
    List<String> unmanagedFiles = [];
    var db = openSqliteDatabase(dbPath);
    try {
      // Read ownership once: querying an unindexed table for every file makes
      // startup scanning quadratic in the number of cache entries.
      final managedFiles = {
        for (final row in db.select('SELECT dir, name FROM cache'))
          (row['dir'] as String, row['name'] as String),
      };
      await for (var file in Directory(dir).list(recursive: true)) {
        if (file is File) {
          var size = await file.length();
          var segments = file.uri.pathSegments;
          var name = segments.last;
          var dir = segments.elementAtOrNull(segments.length - 2) ?? "*";
          if (!managedFiles.contains((dir, name))) {
            unmanagedFiles.add(file.path);
          } else {
            totalSize += size;
          }
        }
      }
    } finally {
      db.dispose();
    }
    return CacheScanResult(totalSize, unmanagedFiles);
  });
}
