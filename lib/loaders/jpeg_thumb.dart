import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Encodes an already-small bitmap. The expensive full-resolution decode
/// happens elsewhere; this only compresses a few hundred pixels on a side.
Uint8List? jpegFromPixels(Uint8List pixels, int width, int height, {bool bgra = false}) {
  if (width <= 0 || height <= 0) return null;
  final need = width * height * 4;
  if (pixels.length < need) return null;
  final tight = Uint8List(need);
  tight.setRange(0, need, pixels);
  try {
    final decoded = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: tight.buffer,
      numChannels: 4,
      order: bgra ? img.ChannelOrder.bgra : img.ChannelOrder.rgba,
    );
    final encoded = img.encodeJpg(decoded, quality: 72);
    if (encoded.isEmpty) return null;
    return encoded is Uint8List ? encoded : Uint8List.fromList(encoded);
  } catch (_) {
    return null;
  }
}
