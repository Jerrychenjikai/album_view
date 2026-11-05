import 'time_resolution.dart';

/// Horizontal scale and scroll of the infinite time axis.
///
/// [scrollX] is the content-space x that sits on the left edge of the view.
/// Content x of an instant is `timeDays * pixelsPerDay`.
class TimelineViewport {
  static const double defaultPixelsPerDay = 168;

  double pixelsPerDay;
  double scrollX;

  TimelineViewport({
    this.pixelsPerDay = defaultPixelsPerDay,
    this.scrollX = 0,
  });

  static double get maxPixelsPerDay => TimeScale.maxPixelsPerDay;

  double contentToScreen(double contentX) => contentX - scrollX;

  double screenToContent(double screenX) => scrollX + screenX;

  void panBy(double deltaScreenX) {
    scrollX -= deltaScreenX;
  }

  /// Zooms the horizontal scale, keeping the instant under [focalScreenX] fixed.
  /// The caller clamps [minPixelsPerDay] to the "whole library fits" floor.
  void zoomAt({
    required double focalScreenX,
    required double factor,
    required double minPixelsPerDay,
    double? maxPixelsPerDay,
  }) {
    final hi = maxPixelsPerDay ?? TimeScale.maxPixelsPerDay;
    final lo = minPixelsPerDay > hi ? hi : minPixelsPerDay;
    if (factor <= 0 || factor == 1) {
      pixelsPerDay = pixelsPerDay.clamp(lo, hi).toDouble();
      return;
    }
    final current = pixelsPerDay <= 0 ? lo : pixelsPerDay;
    final focalDays = (scrollX + focalScreenX) / current;
    final next = (current * factor).clamp(lo, hi).toDouble();
    pixelsPerDay = next;
    scrollX = focalDays * pixelsPerDay - focalScreenX;
  }
}
