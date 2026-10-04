import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/network/images.dart';

void main() {
  late Directory directory;
  late CacheManager cache;
  CacheManager? previousCache;
  final clients = <Dio>[];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('venera-image-buffer-');
    previousCache = CacheManager.instance;
    cache = CacheManager.open(
      dataPath: directory.path,
      cacheRoot: directory.path,
    );
    CacheManager.instance = cache;
  });

  tearDown(() async {
    ImageDownloader.cancelAllLoadingImages();
    ImageDownloader.debugResetSourceImageLoading();
    ImageDownloader.debugCreateDio = null;
    for (final client in clients) {
      client.close(force: true);
    }
    clients.clear();
    CacheManager.instance = previousCache;
    await cache.dispose();
    directory.deleteSync(recursive: true);
  });

  void respond(List<Uint8List> chunks, {bool knownLength = true}) {
    ImageDownloader.debugCreateDio = (options) {
      final client = Dio(options)
        ..httpClientAdapter = _ChunkAdapter(chunks, knownLength);
      clients.add(client);
      return client;
    };
  }

  const url = 'https://example.invalid/image';
  for (final thumbnail in [false, true]) {
    final label = thumbnail ? 'thumbnail' : 'comic';
    final cacheKey = thumbnail
        ? '$url@source@comic'
        : '$url@source@comic@chapter';
    Stream<ImageDownloadProgress> load() => thumbnail
        ? ImageDownloader.loadThumbnail(url, 'source', 'comic')
        : ImageDownloader.loadComicImage(url, 'source', 'comic', 'chapter');

    for (final knownLength in [false, true]) {
      test(
        '$label combines chunk views and caches bytes: length=$knownLength',
        () async {
          respond([
            Uint8List.fromList([1, 2]),
            Uint8List.sublistView(Uint8List.fromList([99, 3, 4, 88]), 1, 3),
            Uint8List.fromList([255]),
          ], knownLength: knownLength);

          final events = await load().toList();

          expect(events.last.imageBytes, [1, 2, 3, 4, 255]);
          expect(events.last.currentBytes, 5);
          expect(events.last.totalBytes, 5);
          final progress = events.where((event) => event.imageBytes == null);
          expect(
            progress.map((event) => event.currentBytes),
            thumbnail && !knownLength ? <int>[] : [2, 4, 5],
          );
          expect(
            progress.map((event) => event.totalBytes),
            thumbnail && !knownLength
                ? <int?>[]
                : List<int?>.filled(3, knownLength ? 5 : null),
          );
          expect(await (await cache.findCache(cacheKey))!.readAsBytes(), [
            1,
            2,
            3,
            4,
            255,
          ]);
        },
      );
    }

    test(
      '$label retains a single owned chunk without another output copy',
      () async {
        final chunk = Uint8List.fromList([1, 2, 3]);
        respond([chunk]);

        final events = await load().toList();

        expect(events.last.imageBytes, same(chunk));
        expect(await (await cache.findCache(cacheKey))!.readAsBytes(), [
          1,
          2,
          3,
        ]);
      },
    );

    for (final typedResult in [false, true]) {
      test(
        '$label preserves callback byte ownership: typed=$typedResult',
        () async {
          final chunk = Uint8List.fromList([1, 2, 3]);
          final List<int> result = typedResult
              ? Uint8List.fromList([9, 8])
              : <int>[9, 8];
          final callback = _ResponseCallback((args) {
            final input = args.single as Uint8List;
            expect(input, [1, 2, 3]);
            expect(input, isNot(same(chunk)));
            input[0] = 7;
            return result;
          });
          ImageDownloader.configureSourceImageLoading(
            thumbnailLoadingConfig: (source, image) => {'onResponse': callback},
            comicImageLoadingConfig: (source, image, comic, chapter) => {
              'onResponse': callback,
            },
          );
          respond([chunk]);

          final events = await load().toList();

          expect(events.last.imageBytes, [9, 8]);
          expect(events.last.currentBytes, 2);
          expect(events.last.totalBytes, 2);
          expect(chunk, [1, 2, 3]);
          expect(callback.destroyCount, 1);
          if (typedResult) expect(events.last.imageBytes, same(result));
          expect(await (await cache.findCache(cacheKey))!.readAsBytes(), [
            9,
            8,
          ]);
        },
      );
    }
  }
}

class _ChunkAdapter implements HttpClientAdapter {
  _ChunkAdapter(this.chunks, this.knownLength);

  final List<Uint8List> chunks;
  final bool knownLength;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody(
    Stream.fromIterable(chunks),
    200,
    headers: {
      if (knownLength)
        Headers.contentLengthHeader: [
          '${chunks.fold<int>(0, (length, chunk) => length + chunk.length)}',
        ],
    },
  );

  @override
  void close({bool force = false}) {}
}

class _ResponseCallback extends JSInvokable {
  _ResponseCallback(this.callback);

  final dynamic Function(List args) callback;
  int destroyCount = 0;

  @override
  dynamic invoke(List args, [dynamic thisVal]) => callback(args);

  @override
  void destroy() => destroyCount++;
}
