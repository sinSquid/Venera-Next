import 'package:venera_next/foundation/sqlite_transaction.dart';
import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'image_favorites_models.dart';
import 'image_favorites_row.dart';

/// Image favorite storage on a caller-owned connection, without cache or UI.
class ImageFavoritesRepository {
  ImageFavoritesRepository(this.db, {String schema = 'main'})
    : _table = '"${schema.replaceAll('"', '""')}"."image_favorites"';
  final Database db;
  final String _table;

  /// 检查表image_favorites是否存在, 不存在则创建
  void initialize() {
    db.execute(
      "CREATE TABLE IF NOT EXISTS $_table ("
      "id TEXT,"
      "title TEXT NOT NULL,"
      "sub_title TEXT,"
      "author TEXT,"
      "tags TEXT,"
      "translated_tags TEXT,"
      "time int,"
      "max_page int,"
      "source_key TEXT NOT NULL,"
      "image_favorites_ep TEXT NOT NULL,"
      "other TEXT NOT NULL,"
      "PRIMARY KEY (id,source_key)"
      ");",
    );
  }

  // 做排序和去重的操作
  void save(ImageFavoritesComic favorite) {
    // 没有章节了就删掉
    if (favorite.imageFavoritesEp.isEmpty) {
      db.execute(
        """
      delete from $_table
      where id == ? and source_key == ?;
    """,
        [favorite.id, favorite.sourceKey],
      );
    } else {
      // 去重章节
      final chapterNumbers = <int>{};
      final tempImageFavoritesEp = <ImageFavoritesEp>[];
      for (var e in favorite.imageFavoritesEp) {
        // 再做一层保险, 防止出现ep为0的脏数据
        if (e.ep > 0 && chapterNumbers.add(e.ep)) {
          tempImageFavoritesEp.add(e);
        }
      }
      tempImageFavoritesEp.sort((a, b) => a.ep.compareTo(b.ep));
      final finalImageFavoritesEp = <Map<String, dynamic>>[];
      for (var e in tempImageFavoritesEp) {
        final pages = <int>{};
        final uniqueImages = <ImageFavorite>[];
        for (ImageFavorite j in e.imageFavorites) {
          if (j.page > 0 && pages.add(j.page)) {
            uniqueImages.add(j);
          }
        }
        uniqueImages.sort((a, b) => a.page.compareTo(b.page));
        // Build only the persisted fields, avoiding a full JSON round trip of
        // the redundant per-image comic and chapter metadata.
        finalImageFavoritesEp.add({
          'eid': e.eid,
          'ep': e.ep,
          'maxPage': e.maxPage,
          'epName': e.epName,
          'imageFavorites': [
            for (final image in uniqueImages)
              {
                'page': image.page,
                'imageKey': image.imageKey,
                'isAutoFavorite': ?image.isAutoFavorite,
              },
          ],
        });
      }
      if (tempImageFavoritesEp.isEmpty) {
        throw "Error: No ImageFavoritesEp";
      }
      db.execute(
        """
      insert or replace into $_table(id, title, sub_title, author, tags, translated_tags, time, max_page, source_key, image_favorites_ep, other)
      values(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """,
        [
          favorite.id,
          favorite.title,
          favorite.subTitle,
          favorite.author,
          favorite.tags.join(","),
          favorite.translatedTags.join(","),
          favorite.time.millisecondsSinceEpoch,
          favorite.maxPage,
          favorite.sourceKey,
          jsonEncode(finalImageFavoritesEp),
          jsonEncode(favorite.other),
        ],
      );
    }
  }

  List<ImageFavoritesComic> getAll([String? keyword]) {
    ResultSet res;
    if (keyword == null || keyword == "") {
      res = db.select("select * from $_table;");
    } else {
      res = db.select(
        """
    select * from $_table
    WHERE title LIKE ?
    OR sub_title LIKE ?
    OR LOWER(tags) LIKE LOWER(?)
    OR LOWER(translated_tags) LIKE LOWER(?)
    OR author LIKE ?;
    """,
        ['%$keyword%', '%$keyword%', '%$keyword%', '%$keyword%', '%$keyword%'],
      );
    }
    return res.map(imageFavoritesComicFromRow).toList();
  }

  ImageFavoritesComic? find(String id, String sourceKey) {
    var row = db.select(
      """
    select * from $_table
    where id == ? and source_key == ?;
    """,
      [id, sourceKey],
    );
    if (row.isEmpty) {
      return null;
    }
    return imageFavoritesComicFromRow(row.first);
  }

  int count() =>
      db.select('SELECT count(*) AS total FROM $_table;').first['total'] as int;

  void saveAll(Iterable<ImageFavoritesComic> comics) =>
      runSqliteTransaction(db, () {
        for (final comic in comics) {
          save(comic);
        }
      }, immediate: true);
}
