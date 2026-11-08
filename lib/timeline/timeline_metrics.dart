/// Shared by the layout and the widgets so a batch never changes size
/// when the horizontal scale changes — only the time axis zooms.
class TimelineMetrics {
  static const double cardWidth = 142;
  static const double cardHeight = 172;
  static const double fan = 16;
  static const double laneGap = 18;
  static const double horizontalGap = 18;
  static const double rotationLimit = 0.04;
  static const double rulerHeight = 52;

  /// How far the camera may travel past the first and last print.
  /// Half a card left the edge stack against the screen, where the
  /// fan and shadow were sometimes clipped.
  static const double scrollInset = 120;

  static double get footprintWidth => cardWidth + fan * 2;
  static double get footprintHeight => cardHeight + fan;

  /// How many stacks fit across the finite cross-axis without shrinking them.
  static int laneCount(double trackCrossExtent) {
    if (trackCrossExtent <= 0) return 1;
    final slot = footprintHeight + laneGap;
    final lanes = ((trackCrossExtent + laneGap) / slot).floor();
    if (lanes < 1) return 1;
    if (lanes > 3) return 3;
    return lanes;
  }

  /// Smallest pixels-per-day that still keeps same-lane neighbours apart.
  static double minPixelsPerDay(double trackCrossExtent) {
    final lanes = laneCount(trackCrossExtent);
    return (footprintWidth + horizontalGap) / lanes;
  }
}
