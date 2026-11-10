part of 'share_card.dart';

const _filmStyle = _Style(
  asset: '',
  saturate: 0.74,
  frame: Color(0xFF141210),
  ink: Color(0xFFE6D3B0),
  pins: false,
  grain: 0.28,
  film: true,
  layouts: [],
);

const double _filmW = 1152;
const double _filmH = 1728;
const Color _filmPaper = Color(0xFFF4F0E6);
const Color _filmBase = Color(0xFF141210);

int _filmPick(int index, int count) {
  const order = [1, 0, 2, 1, 2, 0, 2, 1, 0];
  final i = index % order.length;
  return order[i < 0 ? i + order.length : i] % count;
}

void _filmGrain(Canvas canvas, Rect rect, ui.Image grain, double amount) {
  canvas.save();
  canvas.clipRect(rect);
  final paint = Paint()
    ..blendMode = BlendMode.overlay
    ..color = Color.fromRGBO(255, 255, 255, amount);
  final multiply = Paint()
    ..blendMode = BlendMode.multiply
    ..color = Color.fromRGBO(255, 255, 255, amount * 0.55);
  final gw = grain.width.toDouble();
  final gh = grain.height.toDouble();
  for (var y = rect.top; y < rect.bottom; y += gh) {
    for (var x = rect.left; x < rect.right; x += gw) {
      canvas.drawImage(grain, Offset(x, y), paint);
      canvas.drawImage(grain, Offset(x, y), multiply);
    }
  }
  canvas.restore();
}

void _filmPhoto(
  Canvas canvas,
  ui.Image photo,
  Rect gate,
  double saturate,
  ui.Image grain,
  double amount,
  double focusX,
  double focusY,
) {
  canvas.save();
  canvas.clipRect(gate);
  final scale = math.max(gate.width / photo.width, gate.height / photo.height);
  final dw = photo.width * scale;
  final dh = photo.height * scale;
  canvas.drawImageRect(
    photo,
    Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
    Rect.fromLTWH(gate.left + (gate.width - dw) * focusX, gate.top + (gate.height - dh) * focusY, dw, dh),
    Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.matrix(_saturation(saturate)),
  );
  canvas.drawRect(gate, Paint()..color = const Color(0x38E6D3B0)..blendMode = BlendMode.multiply);
  canvas.restore();
  _filmGrain(canvas, gate, grain, amount);
}

void _filmStrip(
  Canvas canvas,
  double cw,
  double ch,
  double stripX,
  double stripW,
  List<ui.Image> photos,
  _Style style,
  ui.Image grain,
  bool partial,
  double phase,
  double angle,
) {
  final rebate = stripW * 0.15;
  final frameW = stripW - rebate * 2;
  final frameH = frameW * 1.5;
  final gap = frameH * 0.095;
  final pitch = frameH + gap;
  final total = frameH * 3 + gap * 2;
  final top = (ch - total) / 2;
  final bleed = ch * 0.14;
  final pivot = Offset(stripX + stripW / 2, ch / 2);
  canvas.save();
  canvas.clipRect(Rect.fromLTWH(0, 0, cw, ch));
  canvas.translate(pivot.dx, pivot.dy);
  canvas.rotate(angle);
  canvas.translate(-pivot.dx, -pivot.dy);
  canvas.drawRect(
    Rect.fromLTWH(stripX, 6, stripW, ch),
    Paint()
      ..color = const Color(0x47282012)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
  );
  canvas.drawRect(Rect.fromLTWH(stripX, -bleed, stripW, ch + bleed * 2), Paint()..color = _filmBase);
  final holeW = stripW * 0.052;
  final holeH = stripW * 0.074;
  final holePitch = stripW * 0.136;
  final holeInset = stripW * 0.04;
  final holePaint = Paint()..color = _filmPaper;
  for (final side in [0, 1]) {
    final hx = side == 0 ? stripX + holeInset : stripX + stripW - holeInset - holeW;
    for (var hy = -bleed; hy < ch + bleed; hy += holePitch) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(hx, hy, holeW, holeH), Radius.circular(holeW * 0.2)),
        holePaint,
      );
    }
  }
  final count = photos.length;
  final gates = <({double y, int index, int photo})>[];
  if (partial) {
    for (var index = 0; index < 6; index++) {
      gates.add((
        y: top - pitch + phase * pitch + index * pitch,
        index: index,
        photo: count > 0 ? _filmPick(index + ((phase + 2) * 3).round(), count) : -1,
      ));
    }
  } else {
    final place = _occupiedSpots(count);
    for (var index = 0; index < 3; index++) {
      gates.add((y: top + index * pitch, index: index, photo: place.indexOf(index)));
    }
  }
  final edge = Paint()
    ..color = const Color(0x24F4F0E6)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  for (final gate in gates) {
    if (gate.y > ch + bleed || gate.y + frameH < -bleed) continue;
    final rect = Rect.fromLTWH(stripX + rebate, gate.y, frameW, frameH);
    if (gate.photo >= 0) {
      final focus = partial ? 0.28 + ((gate.index * 2 + 1) % 5) * 0.11 : 0.5;
      final focusY = partial ? 0.28 + ((gate.index * 3 + 2) % 5) * 0.11 : 0.5;
      _filmPhoto(canvas, photos[gate.photo], rect, style.saturate, grain, style.grain, focus, focusY);
    }
    canvas.drawRect(rect.deflate(0.5), edge);
  }
  const midLabels = ['18', '18A', '19'];
  const sideLabels = ['7', '7A', '8', '8A', '9', '9A'];
  for (var index = 0; index < gates.length; index++) {
    final gate = gates[index];
    final label = partial ? sideLabels[index] : midLabels[index];
    final ny = gate.y + frameH * 0.5;
    final nx = stripX < 0 ? stripX + stripW - rebate * 0.5 : stripX + rebate * 0.5;
    if (nx < 8 || nx > cw - 8 || ny < 0 || ny > ch) continue;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(color: const Color(0xC8E6D3B0), fontSize: math.max(11, stripW * 0.045), fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    canvas.save();
    canvas.translate(nx, ny);
    canvas.rotate(-math.pi / 2);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }
  if (!partial && count > 0) {
    final painter = TextPainter(
      text: TextSpan(
        text: '光桌｜LightTable',
        style: TextStyle(color: const Color(0xE6E6D3B0), fontSize: math.max(13, gap * 0.42), fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    painter.paint(canvas, Offset(stripX + stripW / 2 - painter.width / 2, top + frameH + gap / 2 - painter.height / 2));
  }
  canvas.restore();
}

Future<void> _paintFilm(Canvas canvas, double cw, double ch, List<ui.Image> photos, _Style style) async {
  final grain = await _grainImage();
  final stripW = cw * 0.4;
  canvas.drawRect(Rect.fromLTWH(0, 0, cw, ch), Paint()..color = _filmPaper);
  _filmStrip(canvas, cw, ch, -stripW * 0.62, stripW, photos, style, grain, true, 0.46, -0.11);
  _filmStrip(canvas, cw, ch, cw - stripW * 0.38, stripW, photos, style, grain, true, -0.22, 0.13);
  _filmStrip(canvas, cw, ch, (cw - stripW) / 2, stripW, photos, style, grain, false, 0, 0.055);
}
