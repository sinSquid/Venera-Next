import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/file_interaction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('venera/select_file');

  setUp(() {
    App.cachePath = FilePath.join(
      Directory.systemTemp.path,
      'venera-selection-test-cache',
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
  });

  test(
    'releasing a desktop selection leaves the original file intact',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'venera-selection-source-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final source = File(FilePath.join(directory.path, 'Book.pdf'))
        ..writeAsBytesSync([1, 2, 3]);
      final selection = FileSelection(source.path);
      expect((await selection.prepare()).path, source.path);
      await selection.dispose();
      expect(source.readAsBytesSync(), [1, 2, 3]);
    },
  );

  test(
    'Android selections are prepared lazily and release their own temporary file once',
    () async {
      final calls = <MethodCall>[];
      final selectedPath = FilePath.join(
        App.cachePath,
        'selected_files',
        'unique',
        'Book.pdf',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'prepareFile') {
              return {'path': selectedPath, 'temporary': true};
            }
            return null;
          });
      final selection = FileSelection.androidDocument(
        uri: 'content://books/1',
        name: 'Book.pdf',
      );
      expect(calls, isEmpty);
      expect(selection.name, 'Book.pdf');

      expect((await selection.prepare()).path, selectedPath);
      expect((await selection.prepare()).path, selectedPath);
      expect(calls.map((call) => call.method), ['prepareFile']);
      expect(calls.single.arguments, 'content://books/1');

      await selection.dispose();
      await selection.dispose();
      expect(calls.map((call) => call.method), ['prepareFile', 'releaseFile']);
      expect(calls.last.arguments, selectedPath);
      await expectLater(selection.prepare(), throwsStateError);
    },
  );

  test('direct source files are never sent to temporary cleanup', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return {
            'path': FilePath.join(Directory.systemTemp.path, 'Book.pdf'),
            'temporary': false,
          };
        });
    final selection = FileSelection.androidDocument(
      uri: 'content://books/1',
      name: 'Book.pdf',
    );
    await selection.prepare();
    await selection.dispose();
    expect(calls, ['prepareFile']);
  });

  test('concurrent preparation copies a document only once', () async {
    final response = Completer<Map<String, dynamic>>();
    var preparations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'prepareFile') {
            preparations++;
            return response.future;
          }
          return null;
        });
    final selection = FileSelection.androidDocument(
      uri: 'content://books/1',
      name: 'Book.pdf',
    );
    final first = selection.prepare();
    final second = selection.prepare();
    await pumpEventQueue();
    expect(preparations, 1);
    response.complete({'path': '/cache/Book.pdf', 'temporary': true});
    expect((await first).path, '/cache/Book.pdf');
    expect((await second).path, '/cache/Book.pdf');
    await selection.dispose();
  });

  test('disposal waits for and releases a late temporary copy once', () async {
    final response = Completer<Map<String, dynamic>>();
    final release = Completer<void>();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'prepareFile') return response.future;
          await release.future;
          return null;
        });
    final selection = FileSelection.androidDocument(
      uri: 'content://books/1',
      name: 'Book.pdf',
    );
    final preparation = expectLater(selection.prepare(), throwsStateError);
    var disposed = false;
    final disposal = selection.dispose().then((_) => disposed = true);
    final secondDisposal = selection.dispose();
    await pumpEventQueue();
    expect(disposed, isFalse);
    response.complete({'path': '/cache/Book.pdf', 'temporary': true});
    await preparation;
    await pumpEventQueue();
    expect(calls, ['prepareFile', 'releaseFile']);
    expect(disposed, isFalse);
    release.complete();
    await Future.wait([disposal, secondDisposal]);
    expect(disposed, isTrue);
    await expectLater(selection.prepare(), throwsStateError);
  });

  test('failed preparation can be retried before disposal', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'prepareFile') {
            if (++attempts == 1) throw PlatformException(code: 'copy_error');
            return {'path': '/source/Book.pdf', 'temporary': false};
          }
          fail('A source file must not be released');
        });
    final selection = FileSelection.androidDocument(
      uri: 'content://books/1',
      name: 'Book.pdf',
    );
    await expectLater(selection.prepare(), throwsA(isA<PlatformException>()));
    expect((await selection.prepare()).path, '/source/Book.pdf');
    expect(attempts, 2);
    await selection.dispose();
  });

  test('disposal completes when pending preparation fails', () async {
    final response = Completer<Map<String, dynamic>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => response.future);
    final selection = FileSelection.androidDocument(
      uri: 'content://books/1',
      name: 'Book.pdf',
    );
    final preparation = expectLater(
      selection.prepare(),
      throwsA(isA<PlatformException>()),
    );
    final disposal = selection.dispose();
    await pumpEventQueue();
    response.completeError(PlatformException(code: 'copy_error'));
    await preparation;
    await disposal;
    await expectLater(selection.prepare(), throwsStateError);
  });

  test(
    'desktop directory selection uses the registered file selector',
    () async {
      if (!App.isDesktop) return;
      const selectorChannel = MethodChannel('plugins.flutter.io/file_selector');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(selectorChannel, (call) async {
            calls.add(call.method);
            return '/selected/comics';
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(selectorChannel, null);
      });
      expect(
        (await DirectoryPicker().pickDirectory())?.path,
        '/selected/comics',
      );
      expect(calls, ['getDirectoryPath']);
      await Future<void>.delayed(const Duration(milliseconds: 110));
    },
  );

  test(
    'unprepared and failed selections do not release unrelated paths',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            throw PlatformException(code: 'prepare_error');
          });
      final unopened = FileSelection.androidDocument(
        uri: 'content://books/1',
        name: 'One.pdf',
      );
      await unopened.dispose();
      expect(calls, isEmpty);

      final broken = FileSelection.androidDocument(
        uri: 'content://books/2',
        name: 'Two.pdf',
      );
      await expectLater(broken.prepare(), throwsA(isA<PlatformException>()));
      await broken.dispose();
      expect(calls, ['prepareFile']);
    },
  );
}
