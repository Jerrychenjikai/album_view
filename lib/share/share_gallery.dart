part of 'share_card.dart';

const _galleryStyle = _Style(
  asset: 'assets/share_gallery.jpg',
  saturate: 1.06,
  frame: Color(0xFFF4EFE6),
  ink: Color(0xFF5C5148),
  pins: false,
  gallery: true,
  layouts: [],
);

class _Spot {
  final double x;
  final double y;
  final double w;

  const _Spot(this.x, this.y, this.w);
}

const List<_Spot> _gallerySpots = [
  _Spot(0.17, 0.37, 0.30),
  _Spot(0.50, 0.35, 0.33),
  _Spot(0.83, 0.37, 0.30),
];

void _paintGallery(Canvas canvas, double cw, double ch, List<ui.Image> photos, _Style style) {
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
  final place = _occupiedSpots(photos.length);
  for (var photoIndex = 0; photoIndex < place.length; photoIndex++) {
    final spot = _gallerySpots[place[photoIndex]];
    _hung(
      canvas,
      cw,
      ch,
      photos[photoIndex],
      _Slot(spot.x, spot.y, spot.w, 0, mark: photos.length >= 2 ? photoIndex == 1 : true),
      style,
    );
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
