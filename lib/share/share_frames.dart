part of 'share_card.dart';

const _framesStyle = _Style(
  asset: 'assets/share_frames.jpg',
  saturate: 1.04,
  frame: Color(0xFFE6DCC4),
  ink: Color(0xFFF3DCB0),
  pins: false,
  frames: true,
  warm: 0.5,
  layouts: [],
);

const List<List<Offset>> _frameNorm = [
  [Offset(0.1840, 0.2778), Offset(0.3443, 0.2873), Offset(0.3119, 0.7005), Offset(0.1493, 0.6684)],
  [Offset(0.4369, 0.2873), Offset(0.6014, 0.2958), Offset(0.5712, 0.7099), Offset(0.4057, 0.6814)],
  [Offset(0.6979, 0.2943), Offset(0.8640, 0.3021), Offset(0.8293, 0.7326), Offset(0.6672, 0.7023)],
];

class _Quad {
  final Offset tl;
  final Offset tr;
  final Offset br;
  final Offset bl;

  const _Quad(this.tl, this.tr, this.br, this.bl);
}

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

Future<List<ui.Image>> _paintFrames(Canvas canvas, double cw, double ch, List<ui.Image> photos, _Style style) async {
  final warmed = <ui.Image>[];
  final place = _occupiedSpots(photos.length);
  for (var photoIndex = 0; photoIndex < place.length; photoIndex++) {
    final graded = await _warmPhoto(photos[photoIndex], style.saturate, style.warm);
    warmed.add(graded);
    _drawIntoQuad(canvas, graded, _frameOpening(place[photoIndex], cw, ch));
  }
  if (photos.isNotEmpty) _frameCaption(canvas, cw, ch);
  return warmed;
}
