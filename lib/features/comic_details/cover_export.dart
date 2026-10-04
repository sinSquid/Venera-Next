import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Encodes the first decoded frame and releases the export's image listener.
Future<Uint8List> readCoverPng(ImageProvider provider) {
  final stream = provider.resolve(ImageConfiguration.empty);
  final result = Completer<Uint8List>();
  late final ImageStreamListener listener;
  var received = false;

  Future<void> encode(ImageInfo info) async {
    try {
      final data = await info.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Failed to encode cover image');
      result.complete(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (error, stack) {
      result.completeError(error, stack);
    } finally {
      info.dispose();
    }
  }

  listener = ImageStreamListener(
    (info, _) {
      if (received) {
        info.dispose();
        return;
      }
      received = true;
      stream.removeListener(listener);
      unawaited(encode(info));
    },
    onError: (Object error, StackTrace? stack) {
      if (received) return;
      received = true;
      stream.removeListener(listener);
      result.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return result.future;
}
