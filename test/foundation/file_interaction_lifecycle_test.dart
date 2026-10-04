import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/foundation/app.dart';
import 'package:venera_next/foundation/file_interaction.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  App.cachePath = Directory.systemTemp.path;
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  testWidgets('overlapping pickers keep selection active until both close', (
    tester,
  ) async {
    final responses = [Completer<String?>(), Completer<String?>()];
    var calls = 0;
    messenger.setMockMethodCallHandler(
      channel,
      (_) => responses[calls++].future,
    );
    final first = selectDirectory();
    final second = selectDirectory();
    await tester.pump();
    responses.first.complete(null);
    await first;
    await tester.pump(const Duration(milliseconds: 150));
    final selectingWithOtherOpen = IO.isSelectingFiles;
    responses.last.complete(null);
    await second;
    await tester.pump(const Duration(milliseconds: 150));
    expect(selectingWithOtherOpen, isTrue);
    expect(IO.isSelectingFiles, isFalse);
  });

  testWidgets('iOS picker errors propagate instead of becoming storage paths', (
    tester,
  ) async {
    const nativeChannel = MethodChannel('venera/method_channel');
    messenger.setMockMethodCallHandler(nativeChannel, (_) async {
      throw PlatformException(code: 'picker_failed');
    });
    addTearDown(() => messenger.setMockMethodCallHandler(nativeChannel, null));
    await expectLater(
      IOSDirectoryPicker.selectDirectory(),
      throwsA(isA<PlatformException>()),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(IO.isSelectingFiles, isFalse);
  });

  group('file saving', () {
    late Directory root;
    late Directory cache;
    late String previousCachePath;
    setUp(() {
      root = Directory.systemTemp.createTempSync('venera-save-file-');
      cache = Directory(FilePath.join(root.path, 'cache'))..createSync();
      previousCachePath = App.cachePath;
      App.cachePath = cache.path;
    });
    tearDown(() {
      App.cachePath = previousCachePath;
      root.deleteSync(recursive: true);
    });

    test(
      'concurrent same-name exports keep independent bytes and cleanup',
      () async {
        final existing = File(FilePath.join(cache.path, 'image.png'))
          ..writeAsBytesSync([9]);
        final responses = [Completer<String?>(), Completer<String?>()];
        final opened = [Completer<void>(), Completer<void>()];
        var calls = 0;
        messenger.setMockMethodCallHandler(channel, (call) {
          expect(call.method, 'getSavePath');
          final index = calls++;
          opened[index].complete();
          return responses[index].future;
        });
        final first = saveFile(
          data: Uint8List.fromList([1]),
          filename: 'image.png',
        );
        await opened.first.future;
        final second = saveFile(
          data: Uint8List.fromList([2]),
          filename: 'image.png',
        );
        await opened.last.future;
        final firstOutput = File(FilePath.join(root.path, 'first.png'));
        final secondOutput = File(FilePath.join(root.path, 'second.png'));
        responses.first.complete(firstOutput.path);
        responses.last.complete(secondOutput.path);
        expect(await first, isTrue);
        expect(await second, isTrue);
        expect(firstOutput.readAsBytesSync(), [1]);
        expect(secondOutput.readAsBytesSync(), [2]);
        expect(existing.readAsBytesSync(), [9]);
        expect(cache.listSync().map((entry) => entry.path), [existing.path]);
      },
    );

    for (final fail in [false, true]) {
      test(
        'temporary export is cleaned after ${fail ? 'failure' : 'cancellation'}',
        () async {
          messenger.setMockMethodCallHandler(channel, (_) async {
            if (fail) throw PlatformException(code: 'save_failed');
            return null;
          });
          final result = saveFile(
            data: Uint8List.fromList([1]),
            filename: 'image.png',
          );
          if (fail) {
            await expectLater(result, throwsA(isA<PlatformException>()));
          } else {
            expect(await result, isFalse);
          }
          expect(cache.listSync(), isEmpty);
        },
      );
    }

    test('a supplied source file is preserved after saving', () async {
      final source = File(FilePath.join(cache.path, 'source.png'))
        ..writeAsBytesSync([3]);
      final output = File(FilePath.join(root.path, 'output.png'));
      messenger.setMockMethodCallHandler(channel, (_) async => output.path);
      expect(await saveFile(file: source, filename: 'image.png'), isTrue);
      expect(source.readAsBytesSync(), [3]);
      expect(output.readAsBytesSync(), [3]);
    });

    test(
      'path separators in a suggested name cannot overwrite other files',
      () async {
        final original = File(FilePath.join(root.path, 'original.png'))
          ..writeAsBytesSync([9]);
        final output = File(FilePath.join(root.path, 'output.png'));
        messenger.setMockMethodCallHandler(channel, (_) async => output.path);
        expect(
          await saveFile(
            data: Uint8List.fromList([1]),
            filename: '../original.png',
          ),
          isTrue,
        );
        expect(original.readAsBytesSync(), [9]);
        expect(output.readAsBytesSync(), [1]);
        expect(cache.listSync(), isEmpty);
      },
    );
  });

  test(
    'file URI overrides decode spaces and Unicode instead of reading escaped paths',
    () async {
      final root = Directory.systemTemp.createTempSync('venera-file-uri-');
      addTearDown(() => root.deleteSync(recursive: true));
      final source = File(FilePath.join(root.path, '漫画 #1%.png'))
        ..writeAsBytesSync([1, 2, 3]);
      final bytes = await overrideIO(
        () => File(source.uri.toString()).readAsBytes(),
      );
      expect(bytes, [1, 2, 3]);
    },
  );
}
