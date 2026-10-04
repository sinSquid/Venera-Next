import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/app_shell/auth_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/local_auth');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('authentication coalesces repeated taps and succeeds once', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var requests = 0;
    var successes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAvailableBiometrics') return ['fingerprint'];
      if (call.method == 'authenticate') {
        requests++;
        return pending.future;
      }
      return true;
    });
    await tester.pumpWidget(
      MaterialApp(home: AuthPage(onSuccessfulAuth: () => successes++)),
    );
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    final overlappingRequests = requests;
    pending.complete(true);
    await tester.pump();
    await tester.pump();
    expect(overlappingRequests, 1);
    expect(successes, 1);
  });

  testWidgets('leaving during capability lookup never starts authentication', (
    tester,
  ) async {
    final capabilities = Completer<List<String>>();
    var requests = 0;
    var successes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAvailableBiometrics') return capabilities.future;
      if (call.method == 'authenticate') requests++;
      return true;
    });
    await tester.pumpWidget(
      MaterialApp(home: AuthPage(onSuccessfulAuth: () => successes++)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    capabilities.complete(['fingerprint']);
    await tester.pump();
    await tester.pump();
    expect(requests, 0);
    expect(successes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving cancels the prompt and ignores late success', (
    tester,
  ) async {
    final pending = Completer<bool>();
    var stopped = 0;
    var successes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAvailableBiometrics') return ['fingerprint'];
      if (call.method == 'authenticate') return pending.future;
      if (call.method == 'stopAuthentication') stopped++;
      return true;
    });
    await tester.pumpWidget(
      MaterialApp(home: AuthPage(onSuccessfulAuth: () => successes++)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete(true);
    await tester.pump();
    await tester.pump();
    expect(stopped, 1);
    expect(successes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('platform failure stays locked and allows a later retry', (
    tester,
  ) async {
    var requests = 0;
    var successes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getAvailableBiometrics') return ['fingerprint'];
      if (call.method == 'authenticate' && ++requests == 1) {
        throw PlatformException(code: 'lockedOut');
      }
      return true;
    });
    await tester.pumpWidget(
      MaterialApp(home: AuthPage(onSuccessfulAuth: () => successes++)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(successes, 0);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump();
    expect(successes, 1);
    expect(requests, 2);
  });
}
