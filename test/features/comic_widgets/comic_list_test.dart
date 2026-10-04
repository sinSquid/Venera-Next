import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/res.dart';

void main() {
  for (final useNext in [false, true]) {
    testWidgets('late page completion after dispose is safe: next=$useNext', (
      tester,
    ) async {
      final oldMode = appdata.settings['comicListDisplayMode'];
      appdata.settings['comicListDisplayMode'] = 'paging';
      addTearDown(() => appdata.settings['comicListDisplayMode'] = oldMode);
      final response = Completer<Res<List<Comic>>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ComicList(
              key: const PageStorageKey('pending'),
              enablePageStorage: true,
              loadPage: useNext ? null : (_) => response.future,
              loadNext: useNext ? (_) => response.future : null,
            ),
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      response.complete(const Res([], subData: null));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unblocking comics gives newly visible tiles valid hero IDs', (
    tester,
  ) async {
    final previousBlocked = appdata.settings['blockedWords'];
    final listeners = <VoidCallback>[];
    configureComicWidgets(
      addStateListener: listeners.add,
      removeStateListener: listeners.remove,
    );
    appdata.settings['blockedWords'] = ['Hidden'];
    addTearDown(() {
      appdata.settings['blockedWords'] = previousBlocked;
      configureComicWidgets();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverGridComics(
                comics: [
                  Comic('Visible', '', '1', null, null, '', 'test', null, null),
                  Comic('Hidden', '', '2', null, null, '', 'test', null, null),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Visible'), findsOneWidget);
    expect(find.text('Hidden'), findsNothing);
    appdata.settings['blockedWords'] = <String>[];
    for (final listener in List.of(listeners)) {
      listener();
    }
    await tester.pump();
    expect(find.text('Hidden'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final heroes = tester.widgetList<Hero>(find.byType(Hero));
    expect(heroes.map((hero) => hero.tag).toSet().length, heroes.length);
    await tester.pumpWidget(const SizedBox());
    expect(listeners, isEmpty);
  });

  testWidgets('ComicList stores mutable page data from unmodifiable results', (
    tester,
  ) async {
    final key = GlobalKey<ComicListState>();
    const comic = Comic(
      'Cat Eye',
      '',
      'cat-eye',
      null,
      null,
      '',
      'webdav_library',
      null,
      null,
    );
    final oldListMode = appdata.settings['comicListDisplayMode'];
    final oldDisplayMode = appdata.settings['comicDisplayMode'];
    final oldBlockedWords = appdata.settings['blockedWords'];
    final oldFavoriteStatus = appdata.settings['showFavoriteStatusOnTile'];
    final oldHistoryStatus = appdata.settings['showHistoryStatusOnTile'];
    final oldUpdateStatus = appdata.settings['showUpdateStatusOnTile'];

    appdata.settings['comicListDisplayMode'] = 'paging';
    appdata.settings['comicDisplayMode'] = 'brief';
    appdata.settings['blockedWords'] = <String>[];
    appdata.settings['showFavoriteStatusOnTile'] = false;
    appdata.settings['showHistoryStatusOnTile'] = false;
    appdata.settings['showUpdateStatusOnTile'] = false;
    addTearDown(() {
      appdata.settings['comicListDisplayMode'] = oldListMode;
      appdata.settings['comicDisplayMode'] = oldDisplayMode;
      appdata.settings['blockedWords'] = oldBlockedWords;
      appdata.settings['showFavoriteStatusOnTile'] = oldFavoriteStatus;
      appdata.settings['showHistoryStatusOnTile'] = oldHistoryStatus;
      appdata.settings['showUpdateStatusOnTile'] = oldUpdateStatus;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStorage(
            bucket: PageStorageBucket(),
            child: ComicList(
              key: key,
              enablePageStorage: true,
              loadPage: (_) async =>
                  Res(List<Comic>.unmodifiable([comic]), subData: 1),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Cat Eye'), findsOneWidget);
    expect(() => key.currentState!.remove(comic), returnsNormally);
    await tester.pump();
    expect(find.text('Cat Eye'), findsNothing);
  });
}
