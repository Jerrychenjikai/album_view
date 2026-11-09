part of 'share_card.dart';

const _boardStyle = _Style(
  asset: 'assets/share_board.jpg',
  saturate: 1.22,
  frame: Color(0xFFF6E7C4),
  ink: Color(0xFF5C4030),
  pins: true,
  layouts: [
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
  ],
);

const List<Color> _pins = [Color(0xFFE24B4B), Color(0xFF3B6FE0), Color(0xFFF0C43A)];
