import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/features/search/aggregated_search_page.dart';
import 'package:venera_next/features/search/search_result_page.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/network/request_scope.dart';

void main() {
  var sources = <ComicSource>[];

  setUp(() {
    configureComicSourceRegistry(
      all: () => List.of(sources),
      find: (key) => sources.where((source) => source.key == key).firstOrNull,
      fromIntKey: (_) => null,
      isEmpty: () => sources.isEmpty,
    );
    final settings = {
      for (final key in ['searchSources', 'comicListDisplayMode'])
        key: appdata.settings[key],
    };
    addTearDown(() {
      settings.forEach((key, value) => appdata.settings[key] = value);
      sources = [];
    });
    appdata.settings['comicListDisplayMode'] = 'paging';
  });

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets(
    'new aggregate query cancels old requests and ignores completion',
    (tester) async {
      final pending = <Completer<Res<List<Comic>>>>[];
      final requests = <RequestScope?>[];
      sources = [
        _Source(
          'test',
          SearchPageData(null, (keyword, page, options) {
            requests.add(RequestScope.current);
            final response = Completer<Res<List<Comic>>>();
            pending.add(response);
            return response.future;
          }, null),
        ),
      ];
      appdata.settings['searchSources'] = ['test'];
      await tester.pumpWidget(host(const AggregatedSearchPage(keyword: 'old')));
      final controller = tester
          .widget<SliverSearchBar>(find.byType(SliverSearchBar))
          .controller;
      controller.onSearch!('new');
      await tester.pump();
      expect(pending, hasLength(2));
      expect(requests.first, isNotNull);
      expect(requests.first!.isCancelled, isTrue);
      pending.last.complete(const Res.error('new result'));
      await tester.pump();
      pending.first.complete(const Res.error('stale result'));
      await tester.pump();
      expect(find.text('new result'), findsOneWidget);
      expect(find.text('stale result'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('aggregate search catches failures and cancels on close', (
    tester,
  ) async {
    final response = Completer<Res<List<Comic>>>();
    RequestScope? request;
    sources = [
      _Source(
        'test',
        SearchPageData(null, null, (_, _, _) {
          request = RequestScope.current;
          return response.future;
        }),
      ),
    ];
    appdata.settings['searchSources'] = ['test'];
    await tester.pumpWidget(host(const AggregatedSearchPage(keyword: 'query')));
    await tester.pumpWidget(const SizedBox());
    expect(request, isNotNull);
    expect(request!.isCancelled, isTrue);
    response.completeError(StateError('late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    sources = [
      _Source(
        'test',
        SearchPageData(null, (_, _, _) async {
          throw StateError('search failed');
        }, null),
      ),
    ];
    await tester.pumpWidget(host(const AggregatedSearchPage(keyword: 'query')));
    await tester.pump();
    expect(find.text('Bad state: search failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('aggregate results create only visible comic tiles', (
    tester,
  ) async {
    final comics = _CountingComicList(1000);
    sources = [
      _Source(
        'test',
        SearchPageData(null, (_, _, _) async {
          return Res(comics);
        }, null),
      ),
    ];
    appdata.settings['searchSources'] = ['test'];
    await tester.pumpWidget(host(const AggregatedSearchPage(keyword: 'query')));
    await tester.pump();
    expect(comics.reads, lessThan(20));
    expect(find.byType(SimpleComicTile).evaluate().length, lessThan(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('result settings own options and can switch a no-option source', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('search-settings-');
    App.dataPath = directory.path;
    final originalHistory = List<String>.of(appdata.searchHistory);
    final calls = <List<String>>[];
    sources = [
      _Source(
        'plain',
        SearchPageData(null, (_, _, _) async {
          return const Res([], subData: 1);
        }, null),
      ),
      _Source(
        'filtered',
        SearchPageData(
          [
            SearchOptions(
              LinkedHashMap.of({'all': 'All', 'new': 'Newest'}),
              'Order',
              'select',
              'all',
            ),
          ],
          (_, _, options) async {
            calls.add(List.of(options));
            return const Res([], subData: 1);
          },
          null,
        ),
      ),
    ];
    appdata.settings['searchSources'] = ['plain', 'filtered'];
    final callerOptions = <String>['all'];
    await tester.pumpWidget(
      host(
        SearchResultPage(
          text: 'query',
          sourceKey: 'filtered',
          options: callerOptions,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Newest'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(calls.last, ['new']);
    expect(callerOptions, ['all']);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      host(const SearchResultPage(text: 'query', sourceKey: 'plain')),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.text('filtered'));
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(calls.last, ['all']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    var saved = false;
    final save = appdata.saveData(false).then((_) => saved = true);
    for (var i = 0; i < 100 && !saved; i++) {
      await tester.pump();
      await tester.runAsync(() => pumpEventQueue());
    }
    expect(saved, isTrue);
    await save;
    appdata.searchHistory = originalHistory;
    directory.deleteSync(recursive: true);
  });
}

class _Source extends Fake implements ComicSource {
  _Source(this.key, this.searchPageData);

  @override
  final String key;
  @override
  String get name => key;
  @override
  final SearchPageData searchPageData;
  @override
  bool get enableTagsSuggestions => false;
  @override
  Map<String, Map<String, String>>? get translations => null;
}

class _CountingComicList extends ListBase<Comic> {
  _CountingComicList(this.length);

  int reads = 0;

  @override
  int length;

  @override
  Comic operator [](int index) {
    reads++;
    return Comic(
      'Comic $index',
      '',
      '$index',
      null,
      null,
      '',
      'test',
      null,
      null,
    );
  }

  @override
  void operator []=(int index, Comic value) =>
      throw UnsupportedError('read only');
}
