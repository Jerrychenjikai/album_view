part of 'share_card.dart';

const _deskStyle = _Style(
  asset: 'assets/share_desk.jpg',
  saturate: 0.72,
  frame: Color(0xFFB59262),
  ink: Color(0xFF4A3424),
  pins: false,
  layouts: [
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
  ],
);
