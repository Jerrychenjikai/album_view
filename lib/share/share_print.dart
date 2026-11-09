part of 'share_card.dart';

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

Future<void> _paintPrints(
  Canvas canvas,
  double cw,
  double ch,
  List<ui.Image> photos,
  _Style style,
  ui.Image? grain,
) async {
  final slots = style.layouts[photos.length - 1];
  final order = photos.length == 3 ? [0, 2, 1] : List<int>.generate(photos.length, (index) => index);
  for (final index in order) {
    await _polaroid(
      canvas,
      cw,
      ch,
      photos[index],
      slots[index],
      style,
      style.pins ? _pins[index % _pins.length] : null,
      grain,
    );
  }
}
