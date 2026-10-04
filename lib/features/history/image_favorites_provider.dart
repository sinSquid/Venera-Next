import 'dart:async' show Future, StreamController;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/foundation/image_provider/base_image_provider.dart';
import 'package:venera_next/network/images.dart';
import 'package:venera_next/network/image_stream.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/features/history/image_favorites_models.dart';
import 'image_favorites_provider.dart' as image_provider;

class ImageFavoritesProvider
    extends BaseImageProvider<image_provider.ImageFavoritesProvider> {
  /// Image provider for imageFavorites
  const ImageFavoritesProvider(this.imageFavorite);

  final ImageFavorite imageFavorite;

  int get page => imageFavorite.page;

  String get sourceKey => imageFavorite.sourceKey;

  String get cid => imageFavorite.id;

  String get eid => imageFavorite.eid;

  @override
  Future<Uint8List> load(
    StreamController<ImageChunkEvent>? chunkEvents,
    void Function()? checkStop,
  ) async {
    var imageKey = imageFavorite.imageKey;
    var localImage = await getImageFromLocal();
    checkStop?.call();
    if (localImage != null) {
      return localImage;
    }
    var cacheImage = await readFromCache();
    checkStop?.call();
    if (cacheImage != null) {
      return cacheImage;
    }
    var gotImageKey = false;
    if (imageKey == "") {
      imageKey = await getImageKey();
      checkStop?.call();
      gotImageKey = true;
    }
    Uint8List image;
    try {
      image = await getImageFromNetwork(imageKey, chunkEvents, checkStop);
    } catch (e) {
      checkStop?.call();
      if (gotImageKey) {
        rethrow;
      } else {
        imageKey = await getImageKey();
        checkStop?.call();
        image = await getImageFromNetwork(imageKey, chunkEvents, checkStop);
      }
    }
    checkStop?.call();
    await writeToCache(image);
    return image;
  }

  Future<void> writeToCache(Uint8List image) async {
    var fileName = md5.convert(key.codeUnits).toString();
    var file = File(FilePath.join(App.cachePath, 'image_favorites', fileName));
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
    await file.writeAsBytes(image);
  }

  Future<Uint8List?> readFromCache() async {
    var fileName = md5.convert(key.codeUnits).toString();
    var file = File(FilePath.join(App.cachePath, 'image_favorites', fileName));
    if (!file.existsSync()) {
      return null;
    }
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      // Cache eviction may finish after the existence check above.
      // A vanished entry is a miss; retain errors for entries still present.
      if (!file.existsSync()) return null;
      rethrow;
    }
  }

  /// Delete a image favorite cache
  static Future<void> deleteFromCache(ImageFavorite imageFavorite) async {
    var fileName = md5
        .convert(ImageFavoritesProvider(imageFavorite).key.codeUnits)
        .toString();
    var file = File(FilePath.join(App.cachePath, 'image_favorites', fileName));
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<Uint8List?> getImageFromLocal() async {
    var localComic = LocalManager().find(cid, ComicType.fromKey(sourceKey));
    if (localComic == null) {
      return null;
    }
    if (localComic.hasChapters && !localComic.chapters!.ids.contains(eid)) {
      return null;
    }
    try {
      final images = await LocalManager().getImages(
        cid,
        ComicType.fromKey(sourceKey),
        eid,
      );
      if (page < 1 || page > images.length) return null;
      final image = images[page - 1];
      return await File(image.substring('file://'.length)).readAsBytes();
    } on FileSystemException {
      // A missing/partial download may still be available in cache or online.
      return null;
    }
  }

  Future<Uint8List> getImageFromNetwork(
    String imageKey,
    StreamController<ImageChunkEvent>? chunkEvents,
    void Function()? checkStop,
  ) async {
    final check = checkStop ?? () {};
    final bytes = await readImageStream(
      ImageDownloader.loadComicImage(imageKey, sourceKey, cid, eid),
      cancelSignal: BaseImageProvider.cancelSignalOf(check),
      checkStop: check,
      onProgress: (progress) => chunkEvents?.add(
        ImageChunkEvent(
          cumulativeBytesLoaded: progress.currentBytes,
          expectedTotalBytes: progress.totalBytes,
        ),
      ),
    );
    if (bytes != null) return bytes;
    throw "Error: Empty response body.";
  }

  Future<String> getImageKey() async {
    String sourceKey = imageFavorite.sourceKey;
    String cid = imageFavorite.id;
    String eid = imageFavorite.eid;
    var page = imageFavorite.page;
    var comicSource = ComicSource.find(sourceKey);
    if (comicSource == null) {
      throw "Error: Comic source not found.";
    }
    var res = await comicSource.loadComicPages!(cid, eid);
    return res.data[page - 1];
  }

  @override
  Future<ImageFavoritesProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  String get key =>
      "ImageFavorites ${imageFavorite.imageKey}@${imageFavorite.sourceKey}@${imageFavorite.id}@${imageFavorite.eid}"
      "${imageFavorite.imageKey.isEmpty ? '@page:$page' : ''}";
}
