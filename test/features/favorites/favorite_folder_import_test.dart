import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera_next/features/favorites/favorite_folder_import.dart';
import 'package:venera_next/features/favorites/favorites_repository.dart';

class FailingRepository extends FavoritesRepository {
  FailingRepository(super.db);
  @override
  void createFolder(String folder) {
    super.createFolder(folder);
    final table = '"${folder.replaceAll('"', '""')}"';
    db.execute(
      "CREATE TRIGGER fail_import BEFORE INSERT ON $table WHEN new.id = 'fail' BEGIN SELECT RAISE(ABORT, 'injected'); END;",
    );
  }
}

class CountingOrderRepository extends FavoritesRepository {
  CountingOrderRepository(super.db);

  var orderScans = 0;

  @override
  int maxValue(String folder) {
    orderScans++;
    return super.maxValue(folder);
  }

  @override
  int minValue(String folder) {
    orderScans++;
    return super.minValue(folder);
  }
}

void main() {
  late Database db;
  late FavoritesRepository repository;
  setUp(() {
    db = sqlite3.openInMemory();
    repository = FavoritesRepository(db)..initializeMetadata();
  });
  tearDown(() => db.dispose());
  Map<String, Object> item(String id, [int type = 17]) => {
    'id': id,
    'name': id,
    'author': '',
    'type': type,
    'coverPath': '',
    'tags': ['tag'],
  };
  String package(List<Object?> items) =>
      jsonEncode({'name': 'Folder', 'comics': items});
  (String, dynamic) run(String json, {bool append = true}) =>
      importFavoriteFolder(
        json,
        repository,
        append: append,
        translateTags: (_) => 'translated',
      );

  test(
    'malformed late data and translation failure do not create a folder',
    () {
      expect(
        () => run(
          package([
            item('good'),
            {'name': 'bad'},
          ]),
        ),
        throwsA(isA<TypeError>()),
      );
      expect(repository.folderNames(), isEmpty);
      expect(
        () => importFavoriteFolder(
          package([item('good')]),
          repository,
          append: true,
          translateTags: (_) => throw StateError('translation'),
        ),
        throwsStateError,
      );
      expect(repository.folderNames(), isEmpty);
      for (final invalid in [
        '[]',
        '{"name":"","comics":[]}',
        '{"name":"Folder","comics":{}}',
      ]) {
        expect(() => run(invalid), throwsFormatException);
      }
    },
  );

  test(
    'insert failure rolls back the new table and earlier rows before retry',
    () {
      expect(
        () => importFavoriteFolder(
          package([item('good'), item('fail')]),
          FailingRepository(db),
          append: true,
          translateTags: (_) => '',
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(repository.folderNames(), isEmpty);
      run(package([item('good'), item('retry')]));
      expect(repository.getFolderComics('Folder').map((item) => item.id), [
        'good',
        'retry',
      ]);
    },
  );

  test(
    'collision names, duplicate identity and first/end ordering are retained',
    () {
      repository.createFolder('Folder');
      repository.createFolder('Folder(0)');
      final (folder, _) = run(
        package([item('a'), item('a'), item('b'), item('a', 18)]),
        append: false,
      );
      expect(folder, 'Folder(1)');
      expect(
        repository
            .getFolderComics(folder)
            .map((item) => (item.id, item.type.value)),
        [('a', 18), ('b', 17), ('a', 17)],
      );
      expect(repository.count('Folder'), 0);
      final empty = run(package([])).$1;
      expect(empty, 'Folder(2)');
      expect(repository.count(empty), 0);
    },
  );

  for (final append in [true, false]) {
    test(
      'large ${append ? "append" : "prepend"} import preserves first duplicates without repeated order scans',
      () {
        final counted = CountingOrderRepository(db);
        repository = counted;
        final items = <Map<String, Object>>[];
        for (var index = 0; index < 900; index++) {
          items.add(item('bulk-$index'));
          if (index % 7 == 0) {
            items.add({...item('bulk-$index'), 'name': 'duplicate'});
          }
        }
        items.add(item('bulk-0', 18));
        final (folder, _) = run(package(items), append: append);
        final expected = [
          for (var index = 0; index < 900; index++) ('bulk-$index', 17),
          ('bulk-0', 18),
        ];
        final imported = repository.getFolderComics(folder);
        expect(
          imported.map((comic) => (comic.id, comic.type.value)),
          append ? expected : expected.reversed,
        );
        expect(imported.every((comic) => comic.name == comic.id), isTrue);
        final rows = db.select(
          'SELECT display_order, translated_tags FROM "$folder" ORDER BY display_order;',
        );
        expect(rows.map((row) => row['display_order']), [
          for (var index = 1; index <= expected.length; index++)
            append ? index : index - expected.length - 1,
        ]);
        expect(
          rows.every((row) => row['translated_tags'] == 'translated'),
          isTrue,
        );
        expect(counted.orderScans, 0);
      },
    );
  }
}
