import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/history/image_favorites_models.dart';
import 'package:venera_next/features/history/image_favorites_provider.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('favorite-image-provider-');
    App.dataPath = root.path;
    App.cachePath = root.path;
    LocalManager.resetForTesting();
    LocalManager.debugSkipComicSourceInit = true;
    await LocalManager().init();
  });
  tearDown(() {
    LocalManager.resetForTesting();
    root.deleteSync(recursive: true);
  });

  ImageFavorite favorite(int page, {String eid = 'chapter'}) =>
      ImageFavorite(page, '', false, eid, 'book', 1, 'local', 'Chapter');

  for (final chaptered in [false, true]) {
    test(
      'downloaded favorite reads the correct one-based page: $chaptered',
      () async {
        final directory = Directory(
          '${LocalManager().path}/book${chaptered ? '/chapter' : ''}',
        )..createSync(recursive: true);
        File('${directory.path}/1.png').writeAsBytesSync([1]);
        File('${directory.path}/2.png').writeAsBytesSync([2]);
        await LocalManager().add(
          LocalComic(
            id: 'book',
            title: 'Book',
            subtitle: '',
            tags: const [],
            directory: 'book',
            chapters: chaptered
                ? const ComicChapters({'chapter': 'Chapter'})
                : null,
            cover: '',
            comicType: ComicType.local,
            downloadedChapters: const ['chapter'],
            createdAt: DateTime(2026),
          ),
        );
        expect(await ImageFavoritesProvider(favorite(1)).load(null, null), [1]);
        expect(await ImageFavoritesProvider(favorite(2)).load(null, null), [2]);
        expect(
          await ImageFavoritesProvider(favorite(3)).getImageFromLocal(),
          isNull,
        );
        expect(
          await ImageFavoritesProvider(favorite(0)).getImageFromLocal(),
          isNull,
        );
        if (chaptered) {
          expect(
            await ImageFavoritesProvider(
              favorite(1, eid: 'missing'),
            ).getImageFromLocal(),
            isNull,
          );
        }
      },
    );
  }

  test('favorites without image URLs have separate page caches', () async {
    final first = ImageFavoritesProvider(favorite(1));
    final second = ImageFavoritesProvider(favorite(2));
    await first.writeToCache(Uint8List.fromList([1]));
    await second.writeToCache(Uint8List.fromList([2]));
    expect(first, isNot(second));
    expect(await first.readFromCache(), [1]);
    expect(await second.readFromCache(), [2]);
    await ImageFavoritesProvider.deleteFromCache(first.imageFavorite);
    expect(await second.readFromCache(), [2]);
  });

  test('cancellation does not refresh image URLs or write the cache', () async {
    final provider = _CancellationProbe(favorite(1));
    final result = provider.load(null, () {
      if (provider.cancelled) throw StateError('cancelled');
    });
    await expectLater(result, throwsStateError);
    expect(provider.lookups, 0);
    expect(provider.writes, 0);
  });
}

class _CancellationProbe extends ImageFavoritesProvider {
  _CancellationProbe(ImageFavorite favorite)
    : super(favorite.copyWith(imageKey: 'known'));
  bool cancelled = false;
  int lookups = 0;
  int writes = 0;

  @override
  Future<Uint8List?> getImageFromLocal() async => null;
  @override
  Future<Uint8List?> readFromCache() async => null;
  @override
  Future<String> getImageKey() async {
    lookups++;
    return 'refreshed';
  }

  @override
  Future<Uint8List> getImageFromNetwork(
    String key,
    StreamController<ImageChunkEvent>? events,
    void Function()? checkStop,
  ) async {
    cancelled = true;
    checkStop?.call();
    return Uint8List.fromList([1]);
  }

  @override
  Future<void> writeToCache(Uint8List image) async => writes++;
}
