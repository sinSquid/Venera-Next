import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/button.dart';
import 'package:venera_next/features/comic_details/thumbnails.dart';
import 'package:venera_next/features/comic_source/comic_source.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/network/request_scope.dart';

void main() {
  Widget host(ComicThumbnailLoader load) => MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          ComicThumbnails(
            comicId: 'comic',
            sourceKey: 'test',
            initialThumbnails: const [],
            loadComicThumbnail: load,
            readPage: (_) {},
          ),
        ],
      ),
    ),
  );

  testWidgets(
    'thumbnail retry takes its lock before starting and clears errors',
    (tester) async {
      final pending = Completer<Res<List<String>>>();
      var calls = 0;
      await tester.pumpWidget(
        host((_, _) {
          calls++;
          return calls == 1
              ? Future.value(const Res.error('failed'))
              : pending.future;
        }),
      );
      await tester.pump();
      final retry = tester.widget<Button>(find.byType(Button)).onPressed;
      // Retry and a trailing-grid request may happen within the same frame.
      retry();
      retry();
      await tester.pump();
      pending.complete(const Res([], subData: 'next'));
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
      expect(find.text('failed'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('thumbnail source exceptions can be retried', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host((_, _) {
        if (calls++ == 0) throw StateError('failed');
        return Future.value(const Res([]));
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Bad state: failed'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Bad state: failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing previews cancels loading and ignores late failure', (
    tester,
  ) async {
    final response = Completer<Res<List<String>>>();
    RequestScope? scope;
    await tester.pumpWidget(
      host((_, _) {
        scope = RequestScope.current;
        return response.future;
      }),
    );
    await tester.pumpWidget(const SizedBox());
    response.completeError(StateError('late failure'));
    await tester.pump();
    expect(scope?.isCancelled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
