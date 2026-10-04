import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/components/loading.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/log.dart';
import 'package:venera_next/foundation/res.dart';
import 'package:venera_next/network/request_scope.dart';

class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.load});
  final Future<Res<List<String>>> Function(int) load;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends MultiPageLoadingState<_Probe, String> {
  @override
  Future<Res<List<String>>> loadData(int page) => widget.load(page);
  @override
  Widget buildLoading(BuildContext context) => const Text('loading');
  @override
  Widget buildError(BuildContext context, String error) => Text(error);
  @override
  Widget buildContent(BuildContext context, List<String> data) =>
      Text(data.join(','));
}

void main() {
  Widget host(_Probe probe) => MaterialApp(home: Scaffold(body: probe));

  setUp(() {
    final muted = Log.isMuted;
    Log.isMuted = true;
    addTearDown(() => Log.isMuted = muted);
  });

  testWidgets(
    'reset ignores the old first page and keeps replacement loading',
    (tester) async {
      final key = GlobalKey<_ProbeState>();
      final responses = <Completer<Res<List<String>>>>[];
      final scopes = <RequestScope?>[];
      final pages = <int>[];
      await tester.pumpWidget(
        host(
          _Probe(
            key: key,
            load: (page) {
              pages.add(page);
              scopes.add(RequestScope.current);
              final response = Completer<Res<List<String>>>();
              responses.add(response);
              return response.future;
            },
          ),
        ),
      );
      key.currentState!.reset();
      await tester.pump();
      expect(pages, [1, 1]);
      responses.first.complete(const Res(['old'], subData: 1));
      await tester.pump();
      expect(find.text('loading'), findsOneWidget);
      expect(find.text('old'), findsNothing);
      expect(key.currentState!.isLoading, isTrue);
      expect(scopes.first?.isCancelled, isTrue);
      responses.last.complete(const Res(['new'], subData: 1));
      await tester.pump();
      await tester.pump();
      expect(find.text('new'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reset drops the previous next page and its loading lock', (
    tester,
  ) async {
    final key = GlobalKey<_ProbeState>();
    final pages = <int>[];
    final responses = <Completer<Res<List<String>>>>[];
    await tester.pumpWidget(
      host(
        _Probe(
          key: key,
          load: (page) {
            pages.add(page);
            final response = Completer<Res<List<String>>>();
            responses.add(response);
            return response.future;
          },
        ),
      ),
    );
    responses[0].complete(Res(['first']));
    await tester.pump();
    key.currentState!.nextPage();
    key.currentState!.reset();
    await tester.pump();
    responses[1].complete(const Res(['stale next'], subData: 2));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('loading'), findsOneWidget);
    responses[2].complete(const Res(['replacement']));
    await tester.pump();
    key.currentState!.nextPage();
    expect(pages, [1, 2, 1, 2]);
    responses[3].complete(const Res(['latest next'], subData: 2));
    await tester.pump();
    expect(find.text('replacement,latest next'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('immutable first results can append more pages', (tester) async {
    final key = GlobalKey<_ProbeState>();
    await tester.pumpWidget(
      host(
        _Probe(
          key: key,
          load: (page) async {
            return Res(List<String>.unmodifiable(['page $page']), subData: 2);
          },
        ),
      ),
    );
    await tester.pump();
    key.currentState!.nextPage();
    await tester.pump();
    // Completion updates state after this frame; render that update too.
    await tester.pump();
    expect(find.text('page 1,page 2'), findsOneWidget);
    expect(key.currentState!.haveNextPage, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reset clears an old page limit before loading an unknown total',
    (tester) async {
      final key = GlobalKey<_ProbeState>();
      final pages = <int>[];
      await tester.pumpWidget(
        host(
          _Probe(
            key: key,
            load: (page) async {
              pages.add(page);
              return Res(['page $page'], subData: pages.length == 1 ? 1 : null);
            },
          ),
        ),
      );
      await tester.pump();
      expect(key.currentState!.haveNextPage, isFalse);
      key.currentState!.reset();
      await tester.pump();
      key.currentState!.nextPage();
      await tester.pump();
      await tester.pump();
      expect(pages, [1, 1, 2]);
      expect(find.text('page 1,page 2'), findsOneWidget);
    },
  );

  testWidgets('first and next page exceptions leave retryable state', (
    tester,
  ) async {
    final key = GlobalKey<_ProbeState>();
    final messages = <String>[];
    registerShowMessageHandler((context, message) => messages.add(message));
    addTearDown(() => registerShowMessageHandler((context, message) {}));
    var failFirst = true;
    var failNext = true;
    final pages = <int>[];
    await tester.pumpWidget(
      host(
        _Probe(
          key: key,
          load: (page) {
            pages.add(page);
            if (page == 1 && failFirst) {
              failFirst = false;
              throw StateError('first failed');
            }
            if (page == 2 && failNext) {
              failNext = false;
              return Future.error(StateError('next failed'));
            }
            return Future.value(Res(['page $page'], subData: 2));
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Bad state: first failed'), findsOneWidget);
    expect(key.currentState!.isLoading, isFalse);
    key.currentState!.reset();
    await tester.pump();
    key.currentState!.nextPage();
    await tester.pump();
    expect(find.text('page 1'), findsOneWidget);
    expect(messages, hasLength(1));
    expect(key.currentState!.isLoading, isFalse);
    key.currentState!.nextPage();
    await tester.pump();
    expect(pages, [1, 1, 2, 2]);
    expect(find.text('page 1,page 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose cancels in-flight work and suppresses late errors', (
    tester,
  ) async {
    final response = Completer<Res<List<String>>>();
    RequestScope? scope;
    await tester.pumpWidget(
      host(
        _Probe(
          load: (_) {
            scope = RequestScope.current;
            return response.future;
          },
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    response.completeError(StateError('late failure'));
    await tester.pump();
    expect(scope?.isCancelled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
