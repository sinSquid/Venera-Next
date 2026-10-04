import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_details/favorite.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/favorites/favorites.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/network/request_scope.dart';

void main() {
  late LocalFavoritesManager? previousFavorites;
  late dynamic previousLanguage;
  setUp(() {
    previousFavorites = LocalFavoritesManager.cache;
    previousLanguage = appdata.settings['language'];
    LocalFavoritesManager.cache = _Favorites();
    appdata.settings['language'] = 'en-US';
    registerShowMessageHandler((_, _) {});
  });
  tearDown(() {
    LocalFavoritesManager.cache = previousFavorites;
    appdata.settings['language'] = previousLanguage;
  });

  Widget host(Future<Res<Map<String, String>>> Function() load) {
    final source = _Source(
      FavoriteData(
        key: 'test',
        title: 'Favorites',
        multiFolder: true,
        loadComic: null,
        loadNext: null,
        loadFolders: ([_]) => load(),
      ),
    );
    configureComicSourceRegistry(
      all: () => [source],
      find: (_) => source,
      fromIntKey: (_) => source,
      isEmpty: () => false,
    );
    return MaterialApp(
      home: ComicFavoritePanel(
        cid: 'comic',
        type: const ComicType(42),
        isFavorite: null,
        onFavorite: (_, _) {},
        favoriteItem: FavoriteItem(
          id: 'comic',
          name: 'Comic',
          coverPath: '',
          author: '',
          type: const ComicType(42),
          tags: const [],
        ),
      ),
    );
  }

  for (final throws in [false, true]) {
    testWidgets('folder loading failure can be retried: throws=$throws', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        host(() {
          if (calls++ == 0) {
            if (throws) throw StateError('offline');
            return Future.value(const Res.error('offline'));
          }
          return Future.value(const Res({'folder': 'Recovered'}));
        }),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('offline'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
      expect(find.text('Recovered'), findsOneWidget);
      expect(find.textContaining('offline'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('closing favorites cancels folder loading and ignores results', (
    tester,
  ) async {
    final response = Completer<Res<Map<String, String>>>();
    RequestScope? scope;
    await tester.pumpWidget(
      host(() {
        scope = RequestScope.current;
        return response.future;
      }),
    );
    await tester.pumpWidget(const SizedBox());
    response.complete(const Res({'folder': 'Late'}));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(scope?.isCancelled, isTrue);
  });
}

class _Source extends Fake implements ComicSource {
  _Source(this.favoriteData);
  @override
  final FavoriteData favoriteData;
  @override
  bool get isLogged => true;
}

class _Favorites extends ChangeNotifier implements LocalFavoritesManager {
  @override
  List<String> get folderNames => [];
  @override
  List<String> find(String id, ComicType type) => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
