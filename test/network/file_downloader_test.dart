import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/network/file_downloader.dart';

void main() {
  setUp(() {
    appdata.settings['proxy'] = 'direct';
  });

  tearDown(() {
    appdata.settings['proxy'] = 'system';
  });

  test('FileDownloader rejects non-positive scheduling limits', () {
    for (final value in [0, -1]) {
      expect(
        () => FileDownloader(
          'https://example.com/file',
          'unused',
          maxConcurrent: value,
        ),
        throwsArgumentError,
      );
      expect(
        () => FileDownloader(
          'https://example.com/file',
          'unused',
          chunkSize: value,
        ),
        throwsArgumentError,
      );
    }
  });

  for (final behavior in [
    _RangeBehavior.ignored,
    _RangeBehavior.wrongRange,
    _RangeBehavior.oversized,
    _RangeBehavior.truncated,
  ]) {
    test(
      'FileDownloader rejects ${behavior.name} range responses safely',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'venera-downloader-range-',
        );
        final bytes = List<int>.generate(16 * 1024, (index) => index % 251);
        final server = await _serveBytes(bytes, rangeBehavior: behavior);
        addTearDown(() async {
          await server.close(force: true);
          dir.deleteSync(recursive: true);
        });
        final savePath = '${dir.path}/download.bin';
        final original = [
          ...bytes.take(8 * 1024),
          ...List<int>.filled(8 * 1024, 91),
        ];
        await File(savePath).writeAsBytes(original);
        await File(
          '$savePath.download',
        ).writeAsString('0-8192-8192\n8192-16384-0');
        final downloader = FileDownloader(
          'http://127.0.0.1:${server.port}/download.bin',
          savePath,
          maxConcurrent: 1,
          chunkSize: 8 * 1024,
        );
        final statuses = <DownloadingStatus>[];

        await expectLater(
          downloader.start().forEach(statuses.add),
          throwsStateError,
        );

        final saved = await File(savePath).readAsBytes();
        expect(saved.length, original.length);
        expect(saved.take(8 * 1024), original.take(8 * 1024));
        if (behavior != _RangeBehavior.truncated) {
          expect(saved, original);
        }
        expect(statuses.where((status) => status.isFinished), isEmpty);
        expect(File('$savePath.download').existsSync(), isTrue);
      },
    );
  }

  test(
    'FileDownloader accepts an entire-file response without range support',
    () async {
      final dir = Directory.systemTemp.createTempSync(
        'venera-downloader-whole-',
      );
      final bytes = List<int>.generate(16 * 1024, (index) => index % 251);
      final server = await _serveBytes(
        bytes,
        rangeBehavior: _RangeBehavior.ignored,
      );
      addTearDown(() async {
        await server.close(force: true);
        dir.deleteSync(recursive: true);
      });
      final savePath = '${dir.path}/download.bin';
      final downloader = FileDownloader(
        'http://127.0.0.1:${server.port}/download.bin',
        savePath,
        chunkSize: 32 * 1024,
      );

      final statuses = await downloader.start().toList();

      expect(statuses.last.isFinished, isTrue);
      expect(await File(savePath).readAsBytes(), bytes);
    },
  );

  for (final completedResume in [false, true]) {
    test(
      'FileDownloader finishes ${completedResume ? 'complete resumes' : 'empty files'}',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'venera-downloader-complete-',
        );
        final bytes = completedResume ? [1, 2, 3] : <int>[];
        final server = await _serveBytes(bytes);
        addTearDown(() async {
          await server.close(force: true);
          dir.deleteSync(recursive: true);
        });
        final savePath = '${dir.path}/download.bin';
        if (completedResume) {
          await File(savePath).writeAsBytes(bytes);
          await File('$savePath.download').writeAsString('0-3-3');
        }
        final downloader = FileDownloader(
          'http://127.0.0.1:${server.port}/download.bin',
          savePath,
        );

        final statuses = await downloader.start().toList();

        expect(statuses.single.isFinished, isTrue);
        expect(await File(savePath).readAsBytes(), bytes);
        expect(File('$savePath.download').existsSync(), isFalse);
      },
    );
  }

  for (final staleFileExists in [false, true]) {
    test(
      'FileDownloader discards resume offsets when data is ${staleFileExists ? 'a different size' : 'missing'}',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'venera-downloader-stale-',
        );
        final bytes = List<int>.generate(16 * 1024, (index) => index % 251);
        final server = await _serveBytes(bytes);
        addTearDown(() async {
          await server.close(force: true);
          dir.deleteSync(recursive: true);
        });
        final savePath = '${dir.path}/download.bin';
        if (staleFileExists) {
          await File(savePath).writeAsBytes([9, 9, 9]);
        }
        await File('$savePath.download').writeAsString('0-16384-16384');
        final downloader = FileDownloader(
          'http://127.0.0.1:${server.port}/download.bin',
          savePath,
          chunkSize: 8 * 1024,
        );

        final statuses = await downloader.start().toList();

        expect(statuses.last.isFinished, isTrue);
        expect(await File(savePath).readAsBytes(), bytes);
        expect(File('$savePath.download').existsSync(), isFalse);
      },
    );
  }

  for (final invalidStatus in {
    'duplicate coverage': '0-8192-8192\n0-8192-8192',
    'excess downloaded bytes': '0-8192-16384',
    'out-of-bounds blocks': '16384-32768-16384',
  }.entries) {
    test(
      'FileDownloader preserves files when resume metadata has ${invalidStatus.key}',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'venera-downloader-invalid-',
        );
        final bytes = List<int>.filled(16 * 1024, 7);
        final server = await _serveBytes(bytes);
        addTearDown(() async {
          await server.close(force: true);
          dir.deleteSync(recursive: true);
        });
        final savePath = '${dir.path}/download.bin';
        await File(savePath).writeAsBytes(bytes);
        await File('$savePath.download').writeAsString(invalidStatus.value);
        final downloader = FileDownloader(
          'http://127.0.0.1:${server.port}/download.bin',
          savePath,
        );

        await expectLater(
          downloader.start().drain<void>(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('Invalid download resume status'),
            ),
          ),
        );

        expect(await File(savePath).readAsBytes(), bytes);
        expect(
          await File('$savePath.download').readAsString(),
          invalidStatus.value,
        );
      },
    );
  }

  for (final statusCode in [206, 500]) {
    test(
      'FileDownloader closes an unfinished rejected HTTP $statusCode response',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'venera-downloader-stream-',
        );
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final sockets = <Socket>{};
        final rangeClosed = Completer<void>();
        addTearDown(() async {
          for (final socket in sockets) {
            socket.destroy();
          }
          await server.close();
          dir.deleteSync(recursive: true);
        });
        server.listen((socket) {
          sockets.add(socket);
          var request = '';
          var handled = false;
          var rangeRequest = false;
          void closed() {
            if (rangeRequest && !rangeClosed.isCompleted) {
              rangeClosed.complete();
            }
          }

          socket.listen(
            (data) {
              if (handled) return;
              request += ascii.decode(data);
              if (!request.contains('\r\n\r\n')) return;
              handled = true;
              if (request.startsWith('HEAD ')) {
                socket.write(
                  'HTTP/1.1 200 OK\r\nContent-Length: 16384\r\nConnection: close\r\n\r\n',
                );
                unawaited(socket.close());
              } else {
                rangeRequest = true;
                socket.write(
                  'HTTP/1.1 $statusCode Rejected\r\n'
                  'Content-Length: 16384\r\n'
                  'Content-Range: bytes 1-16383/16384\r\n\r\n',
                );
                // Keep the response unfinished. The client must close it without
                // waiting for the advertised body to finish or a timeout to fire.
                socket.add([1]);
              }
            },
            onDone: closed,
            onError: (Object _) => closed(),
          );
        });
        final downloader = FileDownloader(
          'http://127.0.0.1:${server.port}/download.bin',
          '${dir.path}/download.bin',
        );

        await expectLater(
          downloader.start().drain<void>().timeout(const Duration(seconds: 3)),
          statusCode == 206 ? throwsStateError : throwsA(isA<DioException>()),
        );
        await rangeClosed.future.timeout(const Duration(seconds: 3));
      },
    );
  }

  test('FileDownloader writes concurrent range blocks sequentially', () async {
    final dir = Directory.systemTemp.createTempSync('venera-downloader-');
    final bytes = List<int>.generate(96 * 1024, (index) => index % 251);
    final server = await _serveBytes(bytes);
    addTearDown(() async {
      await server.close(force: true);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    final savePath = '${dir.path}/download.bin';
    final downloader = FileDownloader(
      'http://127.0.0.1:${server.port}/download.bin',
      savePath,
      maxConcurrent: 4,
      chunkSize: 8 * 1024,
    );

    final statuses = await downloader.start().toList();
    final savedBytes = await File(savePath).readAsBytes();

    expect(statuses.last.isFinished, isTrue);
    expect(savedBytes, bytes);
    expect(File('$savePath.download').existsSync(), isFalse);
  });

  test('FileDownloader forwards range errors and closes file handle', () async {
    final dir = Directory.systemTemp.createTempSync('venera-downloader-');
    final bytes = List<int>.generate(32 * 1024, (index) => index % 251);
    final server = await _serveBytes(bytes, failRangeStarts: {8 * 1024});
    addTearDown(() async {
      await server.close(force: true);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    final savePath = '${dir.path}/download.bin';
    final downloader = FileDownloader(
      'http://127.0.0.1:${server.port}/download.bin',
      savePath,
      maxConcurrent: 2,
      chunkSize: 8 * 1024,
    );

    Object? error;
    try {
      await downloader.start().drain<void>();
    } catch (e) {
      error = e;
    }

    expect(error, isA<DioException>());
    expect(File('$savePath.download').existsSync(), isTrue);

    await File(savePath).delete();
    expect(File(savePath).existsSync(), isFalse);
  });

  test(
    'FileDownloader reports incomplete resume status without finish',
    () async {
      final dir = Directory.systemTemp.createTempSync('venera-downloader-');
      final bytes = List<int>.generate(16 * 1024, (index) => index % 251);
      final server = await _serveBytes(bytes);
      addTearDown(() async {
        await server.close(force: true);
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final savePath = '${dir.path}/download.bin';
      // Keep a real data file so only the deliberately incomplete sidecar is
      // invalid; a missing data file must instead discard all resume offsets.
      await File(savePath).writeAsBytes(bytes);
      await File(
        '$savePath.download',
      ).writeAsString('${0}-${8 * 1024}-${8 * 1024}');
      final downloader = FileDownloader(
        'http://127.0.0.1:${server.port}/download.bin',
        savePath,
        maxConcurrent: 1,
        chunkSize: 8 * 1024,
      );

      Object? error;
      final statuses = <DownloadingStatus>[];
      try {
        await for (final status in downloader.start()) {
          statuses.add(status);
        }
      } catch (e) {
        error = e;
      }

      expect(error, isA<FormatException>());
      expect(error.toString(), contains('expected ${16 * 1024} bytes'));
      expect(statuses.where((status) => status.isFinished), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
    },
  );

  test('FileDownloader closes stream when stopped during setup', () async {
    final dir = Directory.systemTemp.createTempSync('venera-downloader-');
    final bytes = List<int>.generate(16 * 1024, (index) => index % 251);
    final headGate = Completer<void>();
    final server = await _serveBytes(
      bytes,
      beforeHeadResponse: headGate.future,
    );
    addTearDown(() async {
      await server.close(force: true);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    });

    final savePath = '${dir.path}/download.bin';
    final downloader = FileDownloader(
      'http://127.0.0.1:${server.port}/download.bin',
      savePath,
      maxConcurrent: 2,
      chunkSize: 8 * 1024,
    );

    final done = downloader.start().drain<void>();
    await pumpEventQueue();
    await downloader.stop();

    headGate.complete();

    await done.timeout(const Duration(seconds: 1));
    if (File(savePath).existsSync()) {
      await File(savePath).delete();
    }
    expect(File(savePath).existsSync(), isFalse);
  });

  test(
    'FileDownloader closes stream when stopped during active block',
    () async {
      final dir = Directory.systemTemp.createTempSync('venera-downloader-');
      final bytes = List<int>.generate(16 * 1024, (index) => index % 251);
      final rangePaused = Completer<void>();
      final rangeGate = Completer<void>();
      final server = await _serveBytes(
        bytes,
        pausedRangeStarts: {0},
        onPausedRangeStart: () {
          if (!rangePaused.isCompleted) {
            rangePaused.complete();
          }
        },
        beforePausedRangeFinish: rangeGate.future,
      );
      addTearDown(() async {
        if (!rangeGate.isCompleted) {
          rangeGate.complete();
        }
        await server.close(force: true);
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      });

      final savePath = '${dir.path}/download.bin';
      final downloader = FileDownloader(
        'http://127.0.0.1:${server.port}/download.bin',
        savePath,
        maxConcurrent: 1,
        chunkSize: 8 * 1024,
      );

      final done = downloader.start().drain<void>();

      await rangePaused.future.timeout(const Duration(seconds: 1));
      await downloader.stop();

      await done.timeout(const Duration(seconds: 1));
    },
  );
}

enum _RangeBehavior { normal, ignored, wrongRange, oversized, truncated }

Future<HttpServer> _serveBytes(
  List<int> data, {
  Set<int> failRangeStarts = const {},
  Future<void>? beforeHeadResponse,
  Set<int> pausedRangeStarts = const {},
  void Function()? onPausedRangeStart,
  Future<void>? beforePausedRangeFinish,
  _RangeBehavior rangeBehavior = _RangeBehavior.normal,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(() async {
    await for (final request in server) {
      await _handleRequest(
        request,
        data,
        failRangeStarts,
        beforeHeadResponse,
        pausedRangeStarts,
        onPausedRangeStart,
        beforePausedRangeFinish,
        rangeBehavior,
      );
    }
  }());
  return server;
}

Future<void> _handleRequest(
  HttpRequest request,
  List<int> data,
  Set<int> failRangeStarts,
  Future<void>? beforeHeadResponse,
  Set<int> pausedRangeStarts,
  void Function()? onPausedRangeStart,
  Future<void>? beforePausedRangeFinish,
  _RangeBehavior rangeBehavior,
) async {
  if (request.method == 'HEAD') {
    await beforeHeadResponse;
    request.response.headers.contentLength = data.length;
    await request.response.close();
    return;
  }

  if (rangeBehavior == _RangeBehavior.ignored) {
    request.response.headers.contentLength = data.length;
    request.response.add(data);
    await request.response.close();
    return;
  }

  var start = 0;
  var end = data.length - 1;
  final range = request.headers.value(HttpHeaders.rangeHeader);
  if (range != null) {
    final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range);
    if (match != null) {
      start = int.parse(match.group(1)!);
      end = int.parse(match.group(2)!);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes ${rangeBehavior == _RangeBehavior.wrongRange ? start + 1 : start}-$end/${data.length}',
      );
    }
  }

  if (failRangeStarts.contains(start)) {
    request.response.statusCode = HttpStatus.internalServerError;
    await request.response.close();
    return;
  }

  var responseStarted = false;
  if (pausedRangeStarts.contains(start)) {
    var firstChunkEnd = start + 1024;
    if (firstChunkEnd > end + 1) {
      firstChunkEnd = end + 1;
    }
    request.response.add(data.sublist(start, firstChunkEnd));
    await request.response.flush();
    responseStarted = true;
    onPausedRangeStart?.call();
    await beforePausedRangeFinish;
    start = firstChunkEnd;
  }

  final body = data.sublist(
    start,
    rangeBehavior == _RangeBehavior.truncated ? end : end + 1,
  );
  if (rangeBehavior == _RangeBehavior.oversized) body.add(0);
  if (!responseStarted) {
    request.response.headers.contentLength = body.length;
  }
  request.response.add(body);
  await request.response.close();
}
