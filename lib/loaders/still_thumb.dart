import 'dart:typed_data';
import 'dart:ui' as ui;

import 'jpeg_thumb.dart';

/// Small JPEG made with the engine's decoder, not the pure-Dart one.
///
/// The Dart `image` decoder inflates a full bitmap on the CPU. Asking the
/// engine for a short edge keeps a 50-photo batch from pinning the machine
/// the first time it is opened. Must run on the root isolate (`dart:ui`).
Future<Uint8List?> stillThumbnail(String path, {int edge = 480}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromFilePath(path);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 || descriptor.height <= 0) return null;
    final wide = descriptor.width >= descriptor.height;
    codec = await descriptor.instantiateCodec(
      targetWidth: wide ? edge : null,
      targetHeight: wide ? null : edge,
    );
    final frame = await codec.getNextFrame();
    image = frame.image;
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) return null;
    return jpegFromPixels(
      raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      image.width,
      image.height,
    );
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

