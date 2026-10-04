import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/features/comic_details/cover_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'synchronous cached frame releases its listener and image handle',
    () async {
      final bytes = Uint8List.fromList([0, 1, 2, 0]);
      final image = _Image(() async => ByteData.sublistView(bytes, 1, 3));
      final stream = _Stream()..cached = ImageInfo(image: image);
      expect(await readCoverPng(_Provider(stream)), [1, 2]);
      expect(stream.listeners, isEmpty);
      expect(image.disposed, isTrue);
      expect(image.format, ui.ImageByteFormat.png);
    },
  );

  test('animated frames cannot complete an export more than once', () async {
    final encoded = Completer<ByteData?>();
    final first = _Image(() => encoded.future);
    final second = _Image(() async => ByteData(1));
    final stream = _Stream();
    final export = readCoverPng(_Provider(stream));
    stream.emit(ImageInfo(image: first));
    expect(stream.listeners, isEmpty);
    stream.emit(ImageInfo(image: second));
    encoded.complete(ByteData(1)..setUint8(0, 7));
    expect(await export, [7]);
    expect(first.disposed, isTrue);
    expect(second.format, isNull);
    second.dispose();
  });

  test('source errors fail the export and release the listener', () async {
    final stream = _Stream();
    final error = StateError('decode failed');
    final exported = expectLater(
      readCoverPng(_Provider(stream)),
      throwsA(same(error)),
    );
    stream.fail(error);
    await exported;
    expect(stream.listeners, isEmpty);
  });

  for (final returnsNull in [false, true]) {
    test(
      'encoding failure releases the frame: returnsNull=$returnsNull',
      () async {
        final image = _Image(() async {
          if (returnsNull) return null;
          throw StateError('encode failed');
        });
        final stream = _Stream()..cached = ImageInfo(image: image);
        await expectLater(readCoverPng(_Provider(stream)), throwsStateError);
        expect(stream.listeners, isEmpty);
        expect(image.disposed, isTrue);
      },
    );
  }
}

class _Provider extends ImageProvider<_Provider> {
  const _Provider(this.stream);
  final ImageStream stream;
  @override
  ImageStream createStream(ImageConfiguration configuration) => stream;
  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    _Provider key,
    ImageErrorListener handleError,
  ) {}
  @override
  Future<_Provider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
}

class _Stream extends ImageStream {
  final listeners = <ImageStreamListener>[];
  ImageInfo? cached;
  @override
  void addListener(ImageStreamListener listener) {
    listeners.add(listener);
    if (cached != null) listener.onImage(cached!, true);
  }

  @override
  void removeListener(ImageStreamListener listener) =>
      listeners.remove(listener);
  void emit(ImageInfo info) {
    for (final listener in listeners.toList()) {
      listener.onImage(info, false);
    }
  }

  void fail(Object error) {
    for (final listener in listeners.toList()) {
      listener.onError!(error, StackTrace.current);
    }
  }
}

class _Image extends Fake implements ui.Image {
  _Image(this.encode);
  final Future<ByteData?> Function() encode;
  bool disposed = false;
  ui.ImageByteFormat? format;
  @override
  List<StackTrace>? debugGetOpenHandleStackTraces() =>
      disposed ? [] : [StackTrace.current];

  @override
  Future<ByteData?> toByteData({
    ui.ImageByteFormat format = ui.ImageByteFormat.rawRgba,
  }) {
    this.format = format;
    return encode();
  }

  @override
  void dispose() => disposed = true;
}
