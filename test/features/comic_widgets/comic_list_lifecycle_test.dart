import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/network/request_scope.dart';

void main() {
  Comic comic(String title) =>
      Comic(title, '', title, null, null, '', 'test', null, null);
  Widget host(ComicList child, {PageStorageBucket? bucket}) => MaterialApp(
    home: Scaffold(
      body: PageStorage(
        bucket: bucket ?? PageStorageBucket(),
        child: KeyedSubtree(key: const PageStorageKey('list'), child: child),
      ),
    ),
  );

  setUp(() {
    final old = {
      for (final key in [
        'comicListDisplayMode',
        'comicDisplayMode',
        'blockedWords',
        'showFavoriteStatusOnTile',
        'showHistoryStatusOnTile',
        'showUpdateStatusOnTile',
      ])
        key: appdata.settings[key],
    };
    appdata.settings['comicListDisplayMode'] = 'paging';
    appdata.settings['comicDisplayMode'] = 'brief';
    appdata.settings['blockedWords'] = <String>[];
    appdata.settings['showFavoriteStatusOnTile'] = false;
    appdata.settings['showHistoryStatusOnTile'] = false;
    appdata.settings['showUpdateStatusOnTile'] = false;
    addTearDown(
      () => old.forEach((key, value) => appdata.settings[key] = value),
    );
  });

  testWidgets('refresh ignores stale pages without unlocking the new request', (
    tester,
  ) async {
    final key = GlobalKey<ComicListState>();
    final responses = <Completer<Res<List<Comic>>>>[];
    final scopes = <RequestScope?>[];
    Widget page() => host(
      ComicList(
        key: key,
        loadPage: (_) {
          scopes.add(RequestScope.current);
          final response = Completer<Res<List<Comic>>>();
          responses.add(response);
          return response.future;
        },
      ),
    );
    await tester.pumpWidget(page());
    key.currentState!.refresh();
    await tester.pump();
    responses[0].complete(Res([comic('stale')], subData: 1));
    await tester.pump();
    await tester.pumpWidget(page());
    final during = key.currentState!.state;
    final dataDuring = Map.of(during['data'] as Map);
    final loadingDuring = Map.of(during['loading'] as Map);
    final callsDuring = responses.length;
    responses[1].complete(Res([comic('fresh')], subData: 1));
    await tester.pump();
    expect(dataDuring, isEmpty);
    // Pending flags are not persisted; a second build must still not duplicate
    // the replacement source call while it is in flight.
    expect(loadingDuring.values.where((value) => value == true), isEmpty);
    expect(callsDuring, 2);
    expect(scopes[0]?.isCancelled, isTrue);
    expect(find.text('fresh'), findsOneWidget);
    expect(find.text('stale'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reload completing after refresh cannot overwrite the new page', (
    tester,
  ) async {
    final key = GlobalKey<ComicListState>();
    final responses = <Completer<Res<List<Comic>>>>[];
    await tester.pumpWidget(
      host(
        ComicList(
          key: key,
          loadPage: (_) {
            final response = Completer<Res<List<Comic>>>();
            responses.add(response);
            return response.future;
          },
        ),
      ),
    );
    responses[0].complete(Res([comic('initial')], subData: 1));
    await tester.pump();
    final reloading = key.currentState!.reload();
    key.currentState!.refresh();
    await tester.pump();
    responses[2].complete(Res([comic('fresh')], subData: 1));
    await tester.pump();
    responses[1].complete(Res([comic('stale reload')], subData: 1));
    await reloading;
    await tester.pump();
    expect(find.text('fresh'), findsOneWidget);
    expect(find.text('stale reload'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final synchronous in [false, true]) {
    testWidgets('thrown page failure can retry: synchronous=$synchronous', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        host(
          ComicList(
            loadPage: (_) {
              if (calls++ == 0) {
                final error = StateError('page failed');
                if (synchronous) throw error;
                return Future.error(error);
              }
              return Future.value(Res([comic('recovered')], subData: 1));
            },
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Bad state: page failed'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(find.text('recovered'), findsOneWidget);
    });
  }

  testWidgets('restoring a pending page starts a new request', (tester) async {
    final key = GlobalKey<ComicListState>();
    final bucket = PageStorageBucket();
    final pages = <int>[];
    final responses = <Completer<Res<List<Comic>>>>[];
    Widget page() => host(
      ComicList(
        key: key,
        enablePageStorage: true,
        loadPage: (page) {
          pages.add(page);
          final response = Completer<Res<List<Comic>>>();
          responses.add(response);
          return response.future;
        },
      ),
      bucket: bucket,
    );
    await tester.pumpWidget(page());
    responses[0].complete(Res([comic('first')], subData: 2));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    key.currentState!.storeState();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    final calls = List.of(pages);
    if (responses.length == 3) {
      responses[2].complete(Res([comic('replacement')], subData: 2));
    }
    responses[1].complete(Res([comic('stale')], subData: 2));
    await tester.pump();
    expect(calls, [1, 2, 2]);
    expect(find.text('replacement'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved pages are independent of later list mutations', (
    tester,
  ) async {
    final key = GlobalKey<ComicListState>();
    final item = comic('saved');
    await tester.pumpWidget(
      host(ComicList(key: key, loadPage: (_) async => Res([item], subData: 1))),
    );
    await tester.pump();
    final snapshot = key.currentState!.state;
    key.currentState!.remove(item);
    await tester.pump();
    expect((snapshot['data'] as Map)[1], [item]);
    expect(find.text('saved'), findsNothing);
  });

  testWidgets('cursor paging shares pending work and stops at the last page', (
    tester,
  ) async {
    final key = GlobalKey<ComicListState>();
    final first = Completer<Res<List<Comic>>>();
    final next = Completer<Res<List<Comic>>>();
    final cursors = <String?>[];
    Widget page() => host(
      ComicList(
        key: key,
        loadNext: (cursor) {
          cursors.add(cursor);
          return cursor == null ? first.future : next.future;
        },
      ),
    );
    appdata.settings['comicListDisplayMode'] = 'continuous';
    await tester.pumpWidget(page());
    first.complete(Res([comic('first')], subData: 'next'));
    await tester.pump();
    await tester.pump();
    expect(cursors, [null, 'next']);
    appdata.settings['comicListDisplayMode'] = 'paging';
    await tester.pumpWidget(page());
    await tester.tap(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pump();
    next.complete(Res([comic('last')]));
    await tester.pump();
    await tester.pump();
    expect(cursors, [null, 'next']);
    expect(key.currentState!.state['maxPage'], 2);
    expect(key.currentState!.state['page'], 2);
    expect(find.text('last'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
