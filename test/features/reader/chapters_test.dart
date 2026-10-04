import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/gesture.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/history/history.dart';
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/features/reader/chapters.dart';
import 'package:venera_next/features/reader/reader_page.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/comic_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('reader-chapters-');
    App.dataPath = directory.path;
    App.cachePath = directory.path;
    LocalManager.resetForTesting();
    LocalManager.debugSkipComicSourceInit = true;
    await LocalManager().init();
  });
  tearDown(() {
    LocalManager.resetForTesting();
    directory.deleteSync(recursive: true);
  });

  Future<void> open(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => Scaffold(body: page)),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final grouped in [false, true]) {
    testWidgets('deep chapter opening does bounded work: grouped=$grouped', (
      tester,
    ) async {
      const count = 3000;
      final data = _CountingMap({for (var i = 1; i <= count; i++) '$i': 'C$i'});
      final chapters = grouped
          ? ComicChapters.grouped({'Group': data})
          : ComicChapters(data);
      final reader = _Reader(chapters, 2500);
      await open(
        tester,
        grouped
            ? ReaderGroupedChaptersView(reader)
            : ReaderChaptersView(reader),
      );
      expect(find.text('C2500'), findsOneWidget);
      debugPrint(
        'Chapter source visits: grouped=$grouped, count=$count, visits=${data.visits}',
      );
      // Includes index creation, but not a traversal from chapter 1 for every row.
      expect(data.visits, lessThan(count * 6));
      final row = find.ancestor(
        of: find.text('C2500'),
        matching: find.byType(ClickInkWell),
      );
      expect(tester.getSize(row).height, 48);
      await tester.tap(find.text('C2500'));
      await tester.pumpAndSettle();
      expect(reader.selected, 2500);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('descending chapters preserve original chapter numbers', (
    tester,
  ) async {
    final data = _CountingMap({for (var i = 1; i <= 20; i++) '$i': 'C$i'});
    final reader = _Reader(ComicChapters(data), 1);
    await open(tester, ReaderChaptersView(reader));
    data.visits = 0;
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();
    expect(data.visits, 0, reason: 'Changing order reuses the chapter index');
    await tester.tap(find.text('C20'));
    await tester.pumpAndSettle();
    expect(reader.selected, 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grouped duplicate IDs keep their global chapter positions', (
    tester,
  ) async {
    const chapters = ComicChapters.grouped({
      'First': {'same': 'A1', 'other': 'A2'},
      'Second': {'same': 'B1', 'another': 'B2'},
    });
    await tester.runAsync(
      () => LocalManager().add(
        LocalComic(
          id: 'book',
          title: 'Book',
          subtitle: '',
          tags: const [],
          directory: 'book',
          chapters: chapters,
          cover: '',
          comicType: ComicType.local,
          downloadedChapters: const ['same'],
          createdAt: DateTime(2026),
        ),
      ),
    );
    final reader = _Reader(chapters, 3);
    await open(tester, ReaderGroupedChaptersView(reader));
    final row = find.ancestor(
      of: find.text('B1'),
      matching: find.byType(ClickInkWell),
    );
    expect(
      find.descendant(
        of: row,
        matching: find.byIcon(Icons.download_done_rounded),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('B2'));
    await tester.pumpAndSettle();
    expect(reader.selected, 4);
    expect(tester.takeException(), isNull);
  });
}

class _CountingMap extends MapBase<String, String> {
  _CountingMap(this.valuesByKey);
  final Map<String, String> valuesByKey;
  int visits = 0;
  @override
  Iterable<String> get keys sync* {
    for (final key in valuesByKey.keys) {
      visits++;
      yield key;
    }
  }

  @override
  int get length => valuesByKey.length;
  @override
  String? operator [](Object? key) {
    visits++;
    return valuesByKey[key];
  }

  @override
  void operator []=(String key, String value) => valuesByKey[key] = value;
  @override
  void clear() => valuesByKey.clear();
  @override
  String? remove(Object? key) => valuesByKey.remove(key);
}

class _Reader extends Fake implements ReaderState {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      'Reader';

  _Reader(ComicChapters chapters, this.chapter)
    : widget = Reader(
        type: ComicType.local,
        cid: 'book',
        name: 'Book',
        chapters: chapters,
        history: History.fromMap({
          'id': 'book',
          'type': 0,
          'time': 1000,
          'title': 'Book',
          'subtitle': '',
          'cover': '',
          'ep': 1,
          'page': 1,
          'max_page': 1,
        }),
        onClosed: () {},
        author: '',
        tags: const [],
      );
  @override
  final Reader widget;
  @override
  final int chapter;
  @override
  String get cid => 'book';
  @override
  ComicType get type => ComicType.local;
  int? selected;
  @override
  bool toChapter(int chapter, {bool toLastPage = false}) {
    selected = chapter;
    return true;
  }
}
