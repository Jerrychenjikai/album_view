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

/// Swiping the preview walks this list.
const List<ShareStyle> shareStyles = [
  ShareStyle('desk', '木桌'),
  ShareStyle('lawn', '草坪'),
  ShareStyle('board', '公告板'),
];

class _Slot {
  final double x;
  final double y;
  final double w;
  final double rot;
  final bool mark;

  const _Slot(this.x, this.y, this.w, this.rot, {this.mark = false});
}

class _Style {
  final String asset;
  final double saturate;
  final Color frame;
  final Color? frameEnd;
  final Color ink;
  final bool pins;
  final List<List<_Slot>> layouts;

  const _Style({
    required this.asset,
    required this.saturate,
    required this.frame,
    required this.ink,
    required this.pins,
    required this.layouts,
    this.frameEnd,
  });
}

const List<List<_Slot>> _deskLayouts = [
  [_Slot(0.50, 0.46, 0.34, -0.035, mark: true)],
  [
    _Slot(0.36, 0.48, 0.30, -0.09),
    _Slot(0.66, 0.45, 0.30, 0.08, mark: true),
  ],
  [
    _Slot(0.30, 0.50, 0.27, -0.11),
    _Slot(0.51, 0.43, 0.30, 0.018, mark: true),
    _Slot(0.72, 0.49, 0.27, 0.10),
  ],
];

const List<List<_Slot>> _lawnLayouts = [
  [_Slot(0.50, 0.54, 0.36, -0.04, mark: true)],
  [
    _Slot(0.34, 0.58, 0.30, -0.12),
    _Slot(0.66, 0.50, 0.30, 0.08, mark: true),
  ],
  [
    _Slot(0.28, 0.60, 0.26, -0.14),
    _Slot(0.52, 0.48, 0.30, 0.02, mark: true),
    _Slot(0.74, 0.58, 0.26, 0.12),
  ],
];

const List<List<_Slot>> _boardLayouts = [
  [_Slot(0.50, 0.50, 0.32, -0.03, mark: true)],
  [
    _Slot(0.34, 0.46, 0.28, -0.06),
    _Slot(0.66, 0.56, 0.28, 0.07, mark: true),
  ],
  [
    _Slot(0.30, 0.40, 0.26, -0.08),
    _Slot(0.52, 0.60, 0.28, 0.02, mark: true),
    _Slot(0.72, 0.42, 0.26, 0.09),
  ],
];

const Map<String, _Style> _styles = {
  'desk': _Style(
    asset: 'assets/share_desk.jpg',
    saturate: 0.72,
    frame: Color(0xFFB59262),
    ink: Color(0xFF4A3424),
    pins: false,
    layouts: _deskLayouts,
  ),
  'lawn': _Style(
    asset: 'assets/share_lawn.jpg',
    saturate: 1.28,
    frame: Color(0xFFFFE7A1),
    frameEnd: Color(0xFFE2B15A),
    ink: Color(0xFF7A4E16),
    pins: false,
    layouts: _lawnLayouts,
  ),
  'board': _Style(
    asset: 'assets/share_board.jpg',
    saturate: 1.22,
    frame: Color(0xFFF6E7C4),
    ink: Color(0xFF5C4030),
    pins: true,
    layouts: _boardLayouts,
  ),
};

const List<Color> _pins = [Color(0xFFE24B4B), Color(0xFF3B6FE0), Color(0xFFF0C43A)];

final Map<String, ui.Image> _backgrounds = {};

Future<ui.Image> _background(String asset) async {
  final cached = _backgrounds[asset];
  if (cached != null) return cached;
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  _backgrounds[asset] = frame.image;
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

void _pin(Canvas canvas, Color color, double pw, double ph) {
  final radius = pw * 0.032;
  canvas.save();
  canvas.translate(0, -ph / 2 + radius * 0.35);
  canvas.drawOval(
    Rect.fromCenter(center: Offset(radius * 0.35, radius * 0.8), width: radius * 1.9, height: radius * 1.1),
    Paint()..color = const Color(0x48000000),
  );
  canvas.drawCircle(Offset.zero, radius, Paint()..color = color);
  canvas.drawCircle(Offset(-radius * 0.28, -radius * 0.28), radius * 0.34, Paint()..color = const Color(0xB3FFFFFF));
  canvas.restore();
}

void _watermark(Canvas canvas, double y, double width, Color color) {
  final size = (width * 0.062).clamp(10.0, 28.0);
  final painter = TextPainter(
    text: TextSpan(
      text: '光桌｜LightTable',
      style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w600),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  );
  painter.layout(maxWidth: width * 0.92);
  painter.paint(canvas, Offset(-painter.width / 2, y - painter.height / 2));
}

void _polaroid(Canvas canvas, double cw, double ch, ui.Image photo, _Slot slot, _Style style, Color? pin) {
  final pw = slot.w * cw;
  final ph = pw * 1.22;
  final pad = pw * 0.065;
  final bottom = ph * 0.2;
  canvas.save();
  canvas.translate(slot.x * cw, slot.y * ch);
  canvas.rotate(slot.rot);
  final frame = Rect.fromCenter(center: Offset.zero, width: pw, height: ph);
  final shadow = Paint()
    ..color = const Color(0x59000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
  canvas.drawRRect(
    RRect.fromRectAndRadius(frame.shift(const Offset(4, 12)), const Radius.circular(5)),
    shadow,
  );
  final fill = Paint();
  final end = style.frameEnd;
  if (end != null) {
    fill.shader = ui.Gradient.linear(frame.topLeft, frame.bottomRight, [style.frame, end]);
  } else {
    fill.color = style.frame;
  }
  canvas.drawRRect(RRect.fromRectAndRadius(frame, const Radius.circular(4)), fill);
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
      ..colorFilter = ColorFilter.matrix(_saturation(style.saturate)),
  );
  canvas.restore();
  if (slot.mark) {
    _watermark(canvas, window.bottom + (frame.bottom - window.bottom) / 2, pw * 0.9, style.ink);
  }
  if (pin != null) _pin(canvas, pin, pw, ph);
  canvas.restore();
}

/// Draws up to three polaroids on the chosen share background.
Future<Uint8List> composeShareCard(List<Uint8List> photos, {String styleId = 'desk'}) async {
  final style = _styles[styleId];
  if (style == null) {
    throw StateError('还没有这个风格');
  }
  final back = await _background(style.asset);
  final decoded = <ui.Image>[];
  for (final bytes in photos.take(3)) {
    final image = await _decode(bytes);
    if (image != null) decoded.add(image);
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(back, Offset.zero, Paint());
  final count = decoded.length;
  if (count > 0) {
    final slots = style.layouts[count - 1];
    final order = count == 3 ? [0, 2, 1] : List<int>.generate(count, (index) => index);
    for (final index in order) {
      _polaroid(
        canvas,
        back.width.toDouble(),
        back.height.toDouble(),
        decoded[index],
        slots[index],
        style,
        style.pins ? _pins[index % _pins.length] : null,
      );
    }
  }
  final picture = recorder.endRecording();
  final out = await picture.toImage(back.width, back.height);
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
