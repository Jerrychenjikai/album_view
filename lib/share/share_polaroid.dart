part of 'share_card.dart';

const _polaroidStyle = _Style(
  asset: 'assets/share_polaroid.jpg',
  saturate: 1,
  frame: Color(0xFFF7F5F0),
  ink: Color(0xFF6E675F),
  pins: false,
  layouts: [],
  pad: 0.058,
  foot: 0.19,
  polaroid: true,
);

void _paintPolaroidDesk(Canvas canvas, ui.Image back, List<ui.Image> photos, _Style style) {
  final cw = back.width.toDouble();
  final ch = back.height.toDouble();
  final lipM = -0.3602 * (ch / 1728) / (cw / 1152);
  final lipB = 435.8 * (ch / 1728);
  const tossed = <List<_Slot>>[
    [],
    [_Slot(0.74, 0.66, 0.44, 0.08)],
    [
      _Slot(0.76, 0.50, 0.40, 0.11),
      _Slot(0.32, 0.74, 0.46, -0.07),
    ],
  ];
  final extra = photos.isEmpty ? const <_Slot>[] : tossed[photos.length - 1];
  final order = extra.length == 2 ? const [1, 0] : List<int>.generate(extra.length, (index) => index);
  for (final slotIndex in order) {
    final slot = extra[slotIndex];
    final pw = slot.w * cw;
    final ph = pw * 1.22;
    canvas.save();
    canvas.translate(slot.x * cw, slot.y * ch);
    canvas.rotate(slot.rot);
    _paintPolaroid(canvas, pw, ph, photos[slotIndex + 1], style, null, false, true, null);
    canvas.restore();
  }
  if (photos.isNotEmpty) {
    final pw = cw * 0.38;
    final ph = pw * 1.22;
    final rot = math.atan(lipM);
    final anchorX = cw * 0.25;
    final anchorY = lipM * anchorX + lipB;
    final tuck = ph * 0.042;
    final sinR = math.sin(rot);
    final cosR = math.cos(rot);
    canvas.save();
    canvas.translate(anchorX - (ph / 2 + tuck) * sinR, anchorY + (ph / 2) * cosR - tuck * cosR);
    canvas.rotate(rot);
    _paintPolaroid(canvas, pw, ph, photos.first, style, null, true, true, null);
    canvas.restore();
  }
  final lipX = cw * 0.46;
  canvas.save();
  canvas.clipPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(cw * 0.48, 0)
      ..lineTo(lipX, lipM * lipX + lipB)
      ..lineTo(0, lipB)
      ..close(),
  );
  canvas.drawImage(back, Offset.zero, Paint());
  canvas.restore();
}
