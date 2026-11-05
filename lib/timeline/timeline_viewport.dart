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
    double pixelsPerDay = defaultPixelsPerDay,
    double? scrollX,
  })  : pixelsPerDay = pixelsPerDay,
        scrollX = scrollX ?? timeDays(DateTime.now()) * pixelsPerDay;

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

/// Keeps the viewport over the photos. Sliding past the first or last
/// photo — where nothing new would enter — is not allowed.
///
/// When the whole span fits, the range collapses to a single centered offset.
double clampTimelineScroll({
  required double scrollX,
  required double pixelsPerDay,
  required double viewWidth,
  required Iterable<double> dayMarks,
  double edgePad = 0,
  double inset = 32,
}) {
  if (viewWidth <= 0 || pixelsPerDay <= 0) return scrollX;
  double? minDays;
  double? maxDays;
  for (final day in dayMarks) {
    if (minDays == null || day < minDays) minDays = day;
    if (maxDays == null || day > maxDays) maxDays = day;
  }
  if (minDays == null || maxDays == null) return scrollX;
  final left = minDays * pixelsPerDay - edgePad;
  final right = maxDays * pixelsPerDay + edgePad;
  final lo = left - inset;
  final hi = right - viewWidth + inset;
  if (hi <= lo) {
    return (left + right) / 2 - viewWidth / 2;
  }
  if (scrollX < lo) return lo;
  if (scrollX > hi) return hi;
  return scrollX;
}