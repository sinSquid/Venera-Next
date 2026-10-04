import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/network/image_stream.dart';
import 'package:venera_next/network/images.dart';
import 'package:venera_next/network/request_scope.dart';

void main() {
  test(
    'without a cancel signal, all chunks are consumed until completion',
    () async {
      var cancelled = false;
      final source = StreamController<ImageDownloadProgress>(
        onCancel: () => cancelled = true,
      );
      final progress = <int>[];
      final result = readImageStream(
        source.stream,
        checkStop: () {},
        onProgress: (event) => progress.add(event.currentBytes),
      );
      for (var i = 1; i <= 3; i++) {
        source.add(ImageDownloadProgress(currentBytes: i, totalBytes: null));
      }
      await source.close();

      expect(await result, isNull);
      expect(progress, [1, 2, 3]);
      expect(cancelled, isTrue);
    },
  );

  test(
    'without a cancel signal, final bytes release the stream early',
    () async {
      var cancelled = false;
      final source = StreamController<ImageDownloadProgress>(
        onCancel: () => cancelled = true,
      );
      final progress = <int>[];
      final result = readImageStream(
        source.stream,
        checkStop: () {},
        onProgress: (event) => progress.add(event.currentBytes),
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      source.add(const ImageDownloadProgress(currentBytes: 1, totalBytes: 3));
      source.add(const ImageDownloadProgress(currentBytes: 2, totalBytes: 3));
      source.add(
        ImageDownloadProgress(
          currentBytes: 3,
          totalBytes: 3,
          imageBytes: bytes,
        ),
      );
      source.add(const ImageDownloadProgress(currentBytes: 4, totalBytes: 4));

      expect(await result, same(bytes));
      expect(progress, [1, 2, 3]);
      expect(cancelled, isTrue);
      expect(source.isClosed, isFalse);
      await source.close();
    },
  );

  test(
    'without a cancel signal, stream errors propagate and unsubscribe',
    () async {
      var cancelled = false;
      final source = StreamController<ImageDownloadProgress>(
        onCancel: () => cancelled = true,
      );
      final error = StateError('download failed');
      final result = readImageStream(source.stream, checkStop: () {});
      final expectation = expectLater(result, throwsA(same(error)));
      source.add(const ImageDownloadProgress(currentBytes: 1, totalBytes: 3));
      source.addError(error);

      await expectation;
      expect(cancelled, isTrue);
      await source.close();
    },
  );

  test(
    'cancels a stalled subscription without waiting for another event',
    () async {
      final scope = RequestScope();
      var cancelled = false;
      final source = StreamController<ImageDownloadProgress>(
        onCancel: () => cancelled = true,
      );
      final result = readImageStream(
        source.stream,
        cancelSignal: scope.whenCancelled,
        checkStop: scope.check,
      );
      final expectation = expectLater(result, throwsA(isA<RequestCancelled>()));
      scope.cancel();
      await expectation;
      expect(cancelled, true);
      await source.close();
      scope.dispose();
    },
  );

  test(
    'returns final bytes and unsubscribes after reporting progress',
    () async {
      final scope = RequestScope();
      var cancelled = false;
      final source = StreamController<ImageDownloadProgress>(
        onCancel: () => cancelled = true,
      );
      final progress = <int>[];
      final result = readImageStream(
        source.stream,
        cancelSignal: scope.whenCancelled,
        checkStop: scope.check,
        onProgress: (event) => progress.add(event.currentBytes),
      );
      final bytes = Uint8List.fromList([1, 2]);
      source.add(const ImageDownloadProgress(currentBytes: 1, totalBytes: 2));
      source.add(
        ImageDownloadProgress(
          currentBytes: 2,
          totalBytes: 2,
          imageBytes: bytes,
        ),
      );
      expect(await result, same(bytes));
      expect(progress, [1, 2]);
      expect(cancelled, true);
      await source.close();
      scope.dispose();
    },
  );

  test(
    'propagates errors and does not publish queued events after cancellation',
    () async {
      final scope = RequestScope();
      final failed = readImageStream(
        Stream.error(StateError('offline')),
        cancelSignal: scope.whenCancelled,
        checkStop: scope.check,
      );
      await expectLater(failed, throwsStateError);
      final source = StreamController<ImageDownloadProgress>();
      var notified = false;
      final pending = readImageStream(
        source.stream,
        cancelSignal: scope.whenCancelled,
        checkStop: scope.check,
        onProgress: (_) => notified = true,
      );
      final expectation = expectLater(
        pending,
        throwsA(isA<RequestCancelled>()),
      );
      source.add(const ImageDownloadProgress(currentBytes: 1, totalBytes: 2));
      scope.cancel();
      await expectation;
      expect(notified, false);
      await source.close();
      scope.dispose();
    },
  );
}
