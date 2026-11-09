part of 'share_card.dart';

const _albumStyle = _Style(
  asset: 'assets/share_album.jpg',
  saturate: 0.74,
  frame: Color(0xFFD9CDB4),
  frameEnd: Color(0xFFB7A88C),
  ink: Color(0xFF6A5E50),
  pins: false,
  grain: 0.28,
  pad: 0.04,
  foot: 0.145,
  layouts: [
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
  ],
);

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
