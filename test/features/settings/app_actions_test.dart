import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/local_comics/local.dart';
import 'package:venera_next/features/settings/app.dart';
import 'package:venera_next/features/settings/setting_components.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/foundation/log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late CacheManager cache;
  late bool previousAuth;

  setUp(() {
    root = Directory.systemTemp.createTempSync('venera-settings-');
    App.dataPath = root.path;
    App.cachePath = '${root.path}/cache';
    LocalManager().path = root.path;
    cache = CacheManager.open(dataPath: root.path, cacheRoot: App.cachePath);
    CacheManager.instance = cache;
    Log.isMuted = true;
    previousAuth = appdata.settings['authorizationRequired'];
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await cache.dispose();
    CacheManager.instance = null;
    LocalManager.resetForTesting();
    Log.isMuted = false;
    appdata.settings['authorizationRequired'] = previousAuth;
    root.deleteSync(recursive: true);
  });

  Future<void> mount(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      MaterialApp(
        navigatorKey: App.rootNavigatorKey,
        home: const Scaffold(body: AppSettings()),
      ),
    );
  }

  void invoke(WidgetTester tester, String title) {
    tester
        .widget<CallbackSetting>(
          find.byWidgetPredicate(
            (widget) => widget is CallbackSetting && widget.title == title,
          ),
        )
        .callback();
  }

  for (final unmount in [false, true]) {
    testWidgets(
      'import picker failure closes waiting dialog: unmount=$unmount',
      (tester) async {
        final selection = Completer<Object?>();
        var selections = 0;
        messenger.setMockMethodCallHandler(channel, (_) async {
          selections++;
          return selections == 1 ? selection.future : null;
        });
        await mount(tester);
        invoke(tester, 'Import App Data');
        invoke(tester, 'Import App Data');
        await tester.pump();
        expect(selections, 1);
        if (unmount) await tester.pumpWidget(const SizedBox());
        selection.completeError(PlatformException(code: 'picker_failed'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        if (!unmount) {
          invoke(tester, 'Import App Data');
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(selections, 2);
          expect(find.byType(LinearProgressIndicator), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }

  testWidgets('cache failure closes waiting dialog and reports the error', (
    tester,
  ) async {
    await tester.runAsync(cache.dispose);
    await mount(tester);
    invoke(tester, 'Clear Cache');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('cancelled import ignores a late file selection', (tester) async {
    final selection = Completer<Object?>();
    messenger.setMockMethodCallHandler(channel, (_) => selection.future);
    await mount(tester);
    invoke(tester, 'Import App Data');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    Log.clear();
    Log.isMuted = false;
    // If consumed, this vanished file would fail copying and log an error.
    selection.complete(['${root.path}/vanished.venera']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(Log.logs.where((item) => item.title == 'Import data'), isEmpty);
    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final unmount in [false, true]) {
    testWidgets(
      'capability failure rolls back authentication: unmount=$unmount',
      (tester) async {
        const authChannel = MethodChannel('plugins.flutter.io/local_auth');
        late Completer<Object?> capabilities;
        messenger.setMockMethodCallHandler(
          authChannel,
          (_) => capabilities.future,
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(authChannel, null),
        );
        await mount(tester);
        appdata.settings['authorizationRequired'] = true;
        final onChanged = tester
            .widget<SwitchSetting>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is SwitchSetting &&
                    widget.settingKey == 'authorizationRequired',
              ),
            )
            .onChanged!;
        // Keep the plugin completion and persisted settings in the real IO zone.
        await tester.runAsync(() async {
          capabilities = Completer<Object?>();
          onChanged();
          if (unmount) await tester.pumpWidget(const SizedBox());
          capabilities.completeError(
            PlatformException(code: 'capability_failed'),
          );
          await Future<void>.delayed(Duration.zero);
          await appdata.saveData(false);
        });
        await tester.pump();
        await tester.pump();
        expect(appdata.settings['authorizationRequired'], isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4));
      },
    );
  }
}
