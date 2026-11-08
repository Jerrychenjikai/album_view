import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

const int sharePhotoLimit = 100;

class ShareStyle {
  final String id;
  final String label;

  const ShareStyle(this.id, this.label);
}

/// Swiping the preview walks this list. Only the desk is drawn for now.
const List<ShareStyle> shareStyles = [ShareStyle('desk', '木桌')];

class _Slot {
  final double x;
  final double y;
  final double w;
  final double rot;

  const _Slot(this.x, this.y, this.w, this.rot);
}

const List<List<_Slot>> _layouts = [
  [_Slot(0.50, 0.46, 0.34, -0.035)],
  [
    _Slot(0.36, 0.48, 0.30, -0.09),
    _Slot(0.66, 0.45, 0.30, 0.08),
  ],
  [
    _Slot(0.30, 0.50, 0.27, -0.11),
    _Slot(0.51, 0.43, 0.30, 0.018),
    _Slot(0.72, 0.49, 0.27, 0.10),
  ],
];

ui.Image? _desk;

Future<ui.Image> _deskImage() async {
  final cached = _desk;
  if (cached != null) return cached;
  final data = await rootBundle.load('assets/share_desk.jpg');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  _desk = frame.image;
  return frame.image;
}

Future<ui.Image?> _decode(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}

List<double> _saturation(double s) {
  const r = 0.2126;
  const g = 0.7152;
  const b = 0.0722;
  final sr = (1 - s) * r;
  final sg = (1 - s) * g;
  final sb = (1 - s) * b;
  return [
    sr + s, sg, sb, 0, 0,
    sr, sg + s, sb, 0, 0,
    sr, sg, sb + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

void _polaroid(Canvas canvas, double cw, double ch, ui.Image photo, _Slot slot) {
  final pw = slot.w * cw;
  final ph = pw * 1.22;
  final pad = pw * 0.065;
  final bottom = ph * 0.2;
  canvas.save();
  canvas.translate(slot.x * cw, slot.y * ch);
  canvas.rotate(slot.rot);
  final frame = Rect.fromCenter(center: Offset.zero, width: pw, height: ph);
  final shadow = Paint()
    ..color = const Color(0x73000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
  canvas.drawRRect(
    RRect.fromRectAndRadius(frame.shift(const Offset(0, 12)), const Radius.circular(5)),
    shadow,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(frame, const Radius.circular(4)),
    Paint()..color = const Color(0xFFB59262),
  );
  final window = Rect.fromLTWH(
    frame.left + pad,
    frame.top + pad,
    frame.width - pad * 2,
    frame.height - pad - bottom,
  );
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(window, const Radius.circular(2)));
  final scale = math.max(window.width / photo.width, window.height / photo.height);
  final dw = photo.width * scale;
  final dh = photo.height * scale;
  final dest = Rect.fromCenter(center: window.center, width: dw, height: dh);
  canvas.drawImageRect(
    photo,
    Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
    dest,
    Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.matrix(_saturation(0.72)),
  );
  canvas.restore();
  canvas.restore();
}

/// Draws up to three desaturated polaroids on the walnut desk.
Future<Uint8List> composeShareCard(List<Uint8List> photos, {String styleId = 'desk'}) async {
  if (styleId != 'desk') {
    throw StateError('还没有这个风格');
  }
  final desk = await _deskImage();
  final decoded = <ui.Image>[];
  for (final bytes in photos.take(3)) {
    final image = await _decode(bytes);
    if (image != null) decoded.add(image);
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(desk, Offset.zero, Paint());
  final count = decoded.length;
  if (count > 0) {
    final slots = _layouts[count - 1];
    final order = count == 3 ? [0, 2, 1] : List<int>.generate(count, (index) => index);
    for (final index in order) {
      _polaroid(canvas, desk.width.toDouble(), desk.height.toDouble(), decoded[index], slots[index]);
    }
  }
  final picture = recorder.endRecording();
  final out = await picture.toImage(desk.width, desk.height);
  picture.dispose();
  for (final image in decoded) {
    image.dispose();
  }
  final raw = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  final width = out.width;
  final height = out.height;
  out.dispose();
  if (raw == null) return Uint8List(0);
  final tight = Uint8List(width * height * 4);
  tight.setRange(0, tight.length, raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes));
  final encoded = img.encodeJpg(
    img.Image.fromBytes(
      width: width,
      height: height,
      bytes: tight.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ),
    quality: 88,
  );
  return encoded is Uint8List ? encoded : Uint8List.fromList(encoded);
}
