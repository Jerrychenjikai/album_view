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
  ShareStyle('board', '公告板'),
  ShareStyle('gallery', '画廊'),
  ShareStyle('album', '相簿'),
  ShareStyle('frames', '相框'),
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
  final double lie;
  final bool gallery;
  final double grain;
  final double pad;
  final double foot;
  final double warm;
  final bool frames;
  final List<List<_Slot>> layouts;

  const _Style({
    required this.asset,
    required this.saturate,
    required this.frame,
    required this.ink,
    required this.pins,
    required this.layouts,
    this.frameEnd,
    this.lie = 0,
    this.gallery = false,
    this.grain = 0,
    this.pad = 0.065,
    this.foot = 0.2,
    this.warm = 0,
    this.frames = false,
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

const List<List<_Slot>> _albumLayouts = [
  [_Slot(0.71, 0.50, 0.31, 0.045, mark: true)],
  [
    _Slot(0.29, 0.50, 0.27, -0.05),
    _Slot(0.71, 0.48, 0.27, 0.05, mark: true),
  ],
  [
    _Slot(0.29, 0.48, 0.27, -0.04),
    _Slot(0.70, 0.30, 0.21, 0.06),
    _Slot(0.72, 0.65, 0.21, -0.035, mark: true),
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
  'board': _Style(
    asset: 'assets/share_board.jpg',
    saturate: 1.22,
    frame: Color(0xFFF6E7C4),
    ink: Color(0xFF5C4030),
    pins: true,
    layouts: _boardLayouts,
  ),
  'gallery': _Style(
    asset: 'assets/share_gallery.jpg',
    saturate: 1.06,
    frame: Color(0xFFF4EFE6),
    ink: Color(0xFF5C5148),
    pins: false,
    gallery: true,
    layouts: [],
  ),
  'album': _Style(
    asset: 'assets/share_album.jpg',
    saturate: 0.74,
    frame: Color(0xFFD9CDB4),
    frameEnd: Color(0xFFB7A88C),
    ink: Color(0xFF6A5E50),
    pins: false,
    grain: 0.28,
    pad: 0.04,
    foot: 0.145,
    layouts: _albumLayouts,
  ),
  'frames': _Style(
    asset: 'assets/share_frames.jpg',
    saturate: 1.04,
    frame: Color(0xFFE6DCC4),
    ink: Color(0xFFF3DCB0),
    pins: false,
    frames: true,
    warm: 0.5,
    layouts: [],
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

void _paintPolaroid(
  Canvas canvas,
  double pw,
  double ph,
  ui.Image photo,
  _Style style,
  Color? pin,
  bool mark,
  bool castShadow,
  ui.Image? grain,
) {
  final pad = pw * style.pad;
  final bottom = ph * style.foot;
  final frame = Rect.fromCenter(center: Offset.zero, width: pw, height: ph);
  if (castShadow) {
    final shadow = Paint()
      ..color = const Color(0x59000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame.shift(const Offset(4, 12)), const Radius.circular(5)),
      shadow,
    );
  }
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
  if (mark) {
    _watermark(canvas, window.bottom + (frame.bottom - window.bottom) / 2, pw * 0.9, style.ink);
  }
  if (style.grain > 0) {
    canvas.drawRect(
      window,
      Paint()
        ..blendMode = BlendMode.multiply
        ..color = const Color(0x47E6D3B0),
    );
    final speckle = grain;
    if (speckle != null) {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(frame, const Radius.circular(5)));
      final paint = Paint()
        ..blendMode = BlendMode.overlay
        ..color = Color.fromRGBO(255, 255, 255, style.grain);
      final multiply = Paint()
        ..blendMode = BlendMode.multiply
        ..color = Color.fromRGBO(255, 255, 255, style.grain * 0.55);
      for (var y = frame.top; y < frame.bottom; y += speckle.height.toDouble()) {
        for (var x = frame.left; x < frame.right; x += speckle.width.toDouble()) {
          canvas.drawImage(speckle, Offset(x, y), paint);
          canvas.drawImage(speckle, Offset(x, y), multiply);
        }
      }
      canvas.restore();
    }
  }
  if (pin != null) _pin(canvas, pin, pw, ph);
}

void _blitLie(Canvas canvas, ui.Image source, double pitch) {
  final w = source.width.toDouble();
  final h = source.height.toDouble();
  final topScale = 1 - pitch;
  final destH = h * (1 - pitch * 0.62);
  canvas.drawOval(
    Rect.fromCenter(center: Offset(0, destH * 0.36), width: w * 0.72, height: destH * 0.14),
    Paint()..color = const Color(0x48242810),
  );
  const strips = 32;
  final paint = Paint()..filterQuality = FilterQuality.medium;
  for (var i = 0; i < strips; i++) {
    final t0 = i / strips;
    final mid = topScale + (1 - topScale) * (t0 + 0.5 / strips);
    final dw = w * mid;
    final sy = t0 * h;
    final sh = math.min(h / strips + 1.5, h - sy);
    final dy = -destH / 2 + destH * t0;
    final dh = destH / strips + 0.75;
    canvas.drawImageRect(source, Rect.fromLTWH(0, sy, w, sh), Rect.fromLTWH(-dw / 2, dy, dw, dh), paint);
  }
}

Future<void> _polaroid(
  Canvas canvas,
  double cw,
  double ch,
  ui.Image photo,
  _Slot slot,
  _Style style,
  Color? pin,
  ui.Image? grain,
) async {
  final pw = slot.w * cw;
  final ph = pw * 1.22;
  if (style.lie > 0) {
    final width = pw.ceil();
    final height = ph.ceil();
    final recorder = ui.PictureRecorder();
    final local = Canvas(recorder);
    local.translate(width / 2, height / 2);
    _paintPolaroid(local, pw, ph, photo, style, pin, slot.mark, false, grain);
    final picture = recorder.endRecording();
    final raster = await picture.toImage(width, height);
    picture.dispose();
    canvas.save();
    canvas.translate(slot.x * cw, slot.y * ch);
    canvas.rotate(slot.rot);
    _blitLie(canvas, raster, style.lie);
    canvas.restore();
    raster.dispose();
    return;
  }
  canvas.save();
  canvas.translate(slot.x * cw, slot.y * ch);
  canvas.rotate(slot.rot);
  _paintPolaroid(canvas, pw, ph, photo, style, pin, slot.mark, true, grain);
  canvas.restore();
}

class _Spot {
  final double x;
  final double y;
  final double w;
  final int cardSide;

  const _Spot(this.x, this.y, this.w, this.cardSide);
}

const List<_Spot> _gallerySpots = [
  _Spot(0.17, 0.37, 0.30, 1),
  _Spot(0.50, 0.35, 0.33, 1),
  _Spot(0.83, 0.37, 0.30, -1),
];

void _galleryDressing(Canvas canvas, double cw, double ch) {
  for (final spot in _gallerySpots) {
    final center = Offset(spot.x * cw, spot.y * ch);
    final rx = cw * 0.22;
    final ry = ch * 0.4;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1, ry / rx);
    canvas.drawCircle(
      Offset.zero,
      rx,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          rx,
          const [Color(0x80FFF8E6), Color(0x38FFE2B0), Color(0x14D2A86E), Color(0x00B48C50)],
          const [0, 0.32, 0.68, 1],
        ),
    );
    canvas.restore();
  }
}

void _hung(Canvas canvas, double cw, double ch, ui.Image photo, _Slot slot, _Style style) {
  final pw = slot.w * cw;
  final ph = pw * 1.12;
  final edge = pw * 0.028;
  final mat = pw * 0.05;
  final bottom = slot.mark ? pw * 0.11 : mat;
  canvas.save();
  canvas.translate(slot.x * cw, slot.y * ch);
  final outer = Rect.fromCenter(center: Offset.zero, width: pw, height: ph);
  canvas.drawRect(
    outer.shift(const Offset(0, 8)),
    Paint()
      ..color = const Color(0x48202818)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
  );
  canvas.drawRect(outer, Paint()..color = const Color(0xFF2E2924));
  canvas.drawRect(outer.deflate(edge), Paint()..color = style.frame);
  final window = Rect.fromLTWH(
    outer.left + edge + mat,
    outer.top + edge + mat,
    outer.width - (edge + mat) * 2,
    outer.height - edge - mat - bottom,
  );
  canvas.save();
  canvas.clipRect(window);
  final scale = math.max(window.width / photo.width, window.height / photo.height);
  final dest = Rect.fromCenter(center: window.center, width: photo.width * scale, height: photo.height * scale);
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
    _watermark(canvas, window.bottom + (outer.bottom - edge - window.bottom) / 2, pw * 0.86, style.ink);
  }
  canvas.restore();
}

List<int> _occupiedSpots(int count) {
  if (count <= 0) return const [];
  if (count == 1) return const [1];
  if (count == 2) return const [0, 1];
  return const [0, 1, 2];
}

List<_Slot> _gallerySlots(int count) {
  final place = _occupiedSpots(count);
  return [
    for (var photoIndex = 0; photoIndex < place.length; photoIndex++)
      _Slot(
        _gallerySpots[place[photoIndex]].x,
        _gallerySpots[place[photoIndex]].y,
        _gallerySpots[place[photoIndex]].w,
        0,
        mark: count >= 2 ? photoIndex == 1 : true,
      ),
  ];
}

ui.Image? _grainCache;

Future<ui.Image> _grainImage() async {
  final cached = _grainCache;
  if (cached != null) return cached;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final random = math.Random(7);
  final paint = Paint();
  for (var i = 0; i < 1800; i++) {
    final tone = random.nextDouble() < 0.035 ? 78 + random.nextInt(40) : 110 + random.nextInt(130);
    paint.color = Color.fromARGB(255, tone, tone, tone);
    canvas.drawCircle(
      Offset(random.nextDouble() * 180, random.nextDouble() * 180),
      0.25 + random.nextDouble() * 0.55,
      paint,
    );
  }
  for (var i = 0; i < 10; i++) {
    paint.color = random.nextBool() ? const Color(0x28903E20) : const Color(0x33ECD6AA);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(random.nextDouble() * 180, random.nextDouble() * 180),
        width: 2 + random.nextDouble() * 8,
        height: 1.2 + random.nextDouble() * 4,
      ),
      paint,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(180, 180);
  picture.dispose();
  _grainCache = image;
  return image;
}

class _Quad {
  final Offset tl;
  final Offset tr;
  final Offset br;
  final Offset bl;

  const _Quad(this.tl, this.tr, this.br, this.bl);
}

const List<List<Offset>> _frameNorm = [
  [Offset(0.1840, 0.2778), Offset(0.3443, 0.2873), Offset(0.3119, 0.7005), Offset(0.1493, 0.6684)],
  [Offset(0.4369, 0.2873), Offset(0.6014, 0.2958), Offset(0.5712, 0.7099), Offset(0.4057, 0.6814)],
  [Offset(0.6979, 0.2943), Offset(0.8640, 0.3021), Offset(0.8293, 0.7326), Offset(0.6672, 0.7023)],
];

List<Offset> _frameOpening(int index, double cw, double ch) {
  final raw = _frameNorm[index];
  final pts = raw.map((point) => Offset(point.dx * cw, point.dy * ch)).toList();
  final center = pts.reduce((a, b) => a + b) / pts.length.toDouble();
  const outset = 1.03;
  return pts.map((point) => center + (point - center) * outset).toList();
}

/// One 2×2 map of a rectangle onto a parallelogram that covers the opening.
_Quad _coveringPara(List<Offset> opening) {
  final tl = opening[0];
  final tr = opening[1];
  final bl = opening[3];
  final ex = tr.dx - tl.dx;
  final ey = tr.dy - tl.dy;
  final fx = bl.dx - tl.dx;
  final fy = bl.dy - tl.dy;
  final det = ex * fy - ey * fx;
  var scale = 1.0;
  for (final point in opening) {
    final vx = point.dx - tl.dx;
    final vy = point.dy - tl.dy;
    final u = (vx * fy - vy * fx) / det;
    final v = (ex * vy - ey * vx) / det;
    scale = math.max(scale, math.max((u - 0.5).abs() * 2, (v - 0.5).abs() * 2));
  }
  scale *= 1.012;
  final center = Offset((tr.dx + bl.dx) / 2, (tr.dy + bl.dy) / 2);
  Offset grow(Offset point) => center + (point - center) * scale;
  final gtl = grow(tl);
  final gtr = grow(tr);
  final gbl = grow(bl);
  return _Quad(gtl, gtr, gtr + gbl - gtl, gbl);
}

Future<ui.Image> _warmPhoto(ui.Image photo, double saturate, double warm) async {
  final maxW = 960.0;
  final scale = photo.width > maxW ? maxW / photo.width : 1.0;
  final dw = math.max(2.0, photo.width * scale);
  final dh = math.max(2.0, photo.height * scale);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    photo,
    Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
    Rect.fromLTWH(0, 0, dw, dh),
    Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.matrix(_saturation(saturate)),
  );
  if (warm > 0) {
    final bounds = Rect.fromLTWH(0, 0, dw, dh);
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.softLight);
    canvas.drawRect(bounds, Paint()..color = Color.fromRGBO(255, 168, 64, warm));
    canvas.restore();
    canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.multiply);
    canvas.drawRect(bounds, Paint()..color = Color.fromRGBO(255, 214, 160, math.min(0.28, warm * 0.4)));
    canvas.restore();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(dw.ceil(), dh.ceil());
  picture.dispose();
  return image;
}

void _drawIntoQuad(Canvas canvas, ui.Image source, List<Offset> opening) {
  final para = _coveringPara(opening);
  final tl = para.tl;
  final tr = para.tr;
  final bl = para.bl;
  final sw = source.width.toDouble();
  final sh = source.height.toDouble();
  final destW = (tr - tl).distance;
  final destH = (bl - tl).distance;
  final cover = math.max(destW / sw, destH / sh);
  final cropW = destW / cover;
  final cropH = destH / cover;
  final sx = (sw - cropW) / 2;
  final sy = (sh - cropH) / 2;
  final a = (tr.dx - tl.dx) / cropW;
  final b = (tr.dy - tl.dy) / cropW;
  final c = (bl.dx - tl.dx) / cropH;
  final d = (bl.dy - tl.dy) / cropH;
  final e = tl.dx - a * sx - c * sy;
  final f = tl.dy - b * sx - d * sy;
  canvas.save();
  canvas.clipPath(Path()
    ..moveTo(opening[0].dx, opening[0].dy)
    ..lineTo(opening[1].dx, opening[1].dy)
    ..lineTo(opening[2].dx, opening[2].dy)
    ..lineTo(opening[3].dx, opening[3].dy)
    ..close());
  canvas.transform(Float64List.fromList([
    a, b, 0, 0,
    c, d, 0, 0,
    0, 0, 1, 0,
    e, f, 0, 1,
  ]));
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(sx, sy, cropW, cropH),
    Rect.fromLTWH(sx, sy, cropW, cropH),
    Paint()..filterQuality = FilterQuality.medium,
  );
  canvas.restore();
}

void _frameCaption(Canvas canvas, double cw, double ch) {
  final size = (cw * 0.016).clamp(14.0, 28.0);
  final painter = TextPainter(
    text: TextSpan(
      text: '光桌｜LightTable',
      style: TextStyle(color: const Color(0xE6F3DCB0), fontSize: size, fontWeight: FontWeight.w600),
    ),
    textDirection: TextDirection.ltr,
  );
  painter.layout();
  painter.paint(canvas, Offset(cw * 0.51 - painter.width / 2, ch * 0.8 - painter.height / 2));
}

/// Draws up to three prints on the chosen share background.
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
  final cw = back.width.toDouble();
  final ch = back.height.toDouble();
  final count = decoded.length;
  final place = _occupiedSpots(count);
  ui.Image? grain;
  if (style.grain > 0) grain = await _grainImage();
  final warmed = <ui.Image>[];
  if (style.gallery) {
    _galleryDressing(canvas, cw, ch);
    final slots = _gallerySlots(count);
    for (var index = 0; index < slots.length; index++) {
      _hung(canvas, cw, ch, decoded[index], slots[index], style);
    }
  } else if (style.frames) {
    for (var photoIndex = 0; photoIndex < place.length; photoIndex++) {
      final graded = await _warmPhoto(decoded[photoIndex], style.saturate, style.warm);
      warmed.add(graded);
      _drawIntoQuad(canvas, graded, _frameOpening(place[photoIndex], cw, ch));
    }
    if (count > 0) _frameCaption(canvas, cw, ch);
  } else if (count > 0) {
    final slots = style.layouts[count - 1];
    final order = count == 3 ? [0, 2, 1] : List<int>.generate(count, (index) => index);
    for (final index in order) {
      await _polaroid(
        canvas,
        cw,
        ch,
        decoded[index],
        slots[index],
        style,
        style.pins ? _pins[index % _pins.length] : null,
        grain,
      );
    }
  }
  final picture = recorder.endRecording();
  final out = await picture.toImage(back.width, back.height);
  picture.dispose();
  for (final image in decoded) {
    image.dispose();
  }
  for (final image in warmed) {
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
