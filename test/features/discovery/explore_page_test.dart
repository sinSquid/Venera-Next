import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/navigation_bar.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/features/comic_widgets/comic_widgets.dart';
import 'package:venera_next/features/discovery/explore_page.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/res.dart';

void main() {
  testWidgets(
    'mixed explore sections retain their own comics across rebuilds',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Comic comic(String title) =>
          Comic(title, '', title, null, null, '', 'test', null, null);
      final source = _Source([
        ExplorePageData(
          'Mixed',
          ExplorePageType.mixed,
          null,
          null,
          null,
          (_) async => Res([
            [comic('First')],
            ExplorePagePart('Section one', [comic('Middle one')], null),
            [comic('Second')],
            ExplorePagePart('Section two', [comic('Middle two')], null),
            [comic('Last')],
          ], subData: 1),
        ),
      ]);
      configureComicSourceRegistry(
        all: () => [source],
        find: (key) => key == 'test' ? source : null,
        fromIntKey: (_) => null,
        isEmpty: () => false,
      );
      final previousPages = appdata.settings['explore_pages'];
      final previousBlocked = appdata.settings['blockedWords'];
      appdata.settings['explore_pages'] = ['Mixed'];
      appdata.settings['blockedWords'] = <String>[];
      addTearDown(() {
        appdata.settings['explore_pages'] = previousPages;
        appdata.settings['blockedWords'] = previousBlocked;
      });
      final observer = NaviObserver();
      final navigator = GlobalKey<NavigatorState>();
      Widget host() => MaterialApp(
        home: NaviPane(
          paneItems: [
            PaneItemEntry(
              label: 'Explore',
              icon: Icons.explore,
              activeIcon: Icons.explore,
            ),
          ],
          paneActions: const [],
          pageBuilder: (_) => const ExplorePage(),
          observer: observer,
          navigatorKey: navigator,
        ),
      );
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      List<List<String>> groups() => tester
          .widgetList<SliverGridComics>(find.byType(SliverGridComics))
          .map((grid) => grid.comics.map((comic) => comic.title).toList())
          .toList();
      final expected = [
        ['First'],
        ['Middle one'],
        ['Second'],
        ['Middle two'],
        ['Last'],
      ];
      expect(groups(), expected);
      await tester.pumpWidget(host());
      await tester.pump();
      expect(groups(), expected);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _Source extends Fake implements ComicSource {
  _Source(this.explorePages);
  @override
  final List<ExplorePageData> explorePages;
  @override
  String get key => 'test';
  @override
  bool get enableTagsTranslate => false;
  @override
  Map<String, Map<String, String>>? get translations => null;
}
