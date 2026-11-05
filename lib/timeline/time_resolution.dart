import 'timeline_metrics.dart';
import 'day_number.dart';

/// How photos are gathered into one batch.
///
/// From fine to coarse: hour, multiples of 3 hours, day, 3 days, week,
/// 2 weeks, month, multiples of 3 months, year, then multiples of 3 years.
enum TimeUnit { hour, hours, day, days, week, weeks, month, months, year, years }

class TimeResolution {
  final TimeUnit unit;
  final String label;
  final double days;

  /// Hour step, day length, month length, or year span.
  final int step;

  const TimeResolution({
    required this.unit,
    required this.label,
    required this.days,
    this.step = 1,
  });

  static const hour = TimeResolution(unit: TimeUnit.hour, label: '时', days: 1 / 24, step: 1);
  static const day = TimeResolution(unit: TimeUnit.day, label: '日', days: 1, step: 1);
  static const week = TimeResolution(unit: TimeUnit.week, label: '周', days: 7, step: 7);
  static const month = TimeResolution(unit: TimeUnit.month, label: '月', days: 30.436875, step: 1);
  static const year = TimeResolution(unit: TimeUnit.year, label: '年', days: 365.2425, step: 1);

  static TimeResolution years(int span) {
    return TimeResolution(
      unit: TimeUnit.years,
      label: '$span年',
      days: 365.2425 * span,
      step: span,
    );
  }
}

class TimeBucket {
  final String id;
  final String label;
  final double centerDays;

  const TimeBucket({required this.id, required this.label, required this.centerDays});
}

class RulerTick {
  final double days;
  final String label;
  final bool major;

  const RulerTick(this.days, this.label, {this.major = false});
}

class ShadeBand {
  final double startDays;
  final double spanDays;

  const ShadeBand(this.startDays, this.spanDays);
}

class RulerGeometry {
  final List<RulerTick> ticks;
  final List<ShadeBand> bands;

  const RulerGeometry(this.ticks, this.bands);
}

/// Continuous pixels-per-day, plus the bucket size that keeps stacks apart.
class TimeScale {
  /// Widest a single hour is allowed to become. Finer than an hour is not offered.
  static const double maxHourPx = 320;

  static double get maxPixelsPerDay => maxHourPx * 24;

  static const List<TimeResolution> _ladder = [
    TimeResolution.hour,
    TimeResolution(unit: TimeUnit.hours, label: '3时', days: 3 / 24, step: 3),
    TimeResolution(unit: TimeUnit.hours, label: '6时', days: 6 / 24, step: 6),
    TimeResolution(unit: TimeUnit.hours, label: '9时', days: 9 / 24, step: 9),
    TimeResolution(unit: TimeUnit.hours, label: '12时', days: 12 / 24, step: 12),
    TimeResolution(unit: TimeUnit.hours, label: '15时', days: 15 / 24, step: 15),
    TimeResolution(unit: TimeUnit.hours, label: '18时', days: 18 / 24, step: 18),
    TimeResolution(unit: TimeUnit.hours, label: '21时', days: 21 / 24, step: 21),
    TimeResolution.day,
    TimeResolution(unit: TimeUnit.days, label: '3日', days: 3, step: 3),
    TimeResolution.week,
    TimeResolution(unit: TimeUnit.weeks, label: '2周', days: 14, step: 14),
    TimeResolution.month,
    TimeResolution(unit: TimeUnit.months, label: '3月', days: 30.436875 * 3, step: 3),
    TimeResolution(unit: TimeUnit.months, label: '6月', days: 30.436875 * 6, step: 6),
    TimeResolution(unit: TimeUnit.months, label: '9月', days: 30.436875 * 9, step: 9),
    TimeResolution.year,
  ];

  /// Pixels between same-lane neighbours when they sit on adjacent buckets.
  static double laneSpacing(double trackCrossExtent) {
    final lanes = TimelineMetrics.laneCount(trackCrossExtent);
    return (TimelineMetrics.footprintWidth + TimelineMetrics.horizontalGap) / lanes;
  }

  /// Finest bucket that still keeps same-lane stacks from colliding.
  static TimeResolution resolutionFor(double pixelsPerDay, double trackCrossExtent) {
    final ppd = pixelsPerDay <= 0 ? 1e-9 : pixelsPerDay;
    final need = laneSpacing(trackCrossExtent) / ppd;
    for (final item in _ladder) {
      if (item.days + 1e-9 >= need) return item;
    }
    var span = 3;
    while (365.2425 * span + 1e-6 < need && span < 600) {
      span += 3;
    }
    return TimeResolution.years(span);
  }

  /// Smallest scale at which [times] still fit inside [viewWidth].
  static double fitPixelsPerDay(Iterable<DateTime> times, double viewWidth) {
    if (viewWidth <= 0) return 1 / 24;
    double? minDays;
    double? maxDays;
    for (final time in times) {
      final days = timeDays(time.toLocal());
      if (minDays == null || days < minDays) minDays = days;
      if (maxDays == null || days > maxDays) maxDays = days;
    }
    if (minDays == null || maxDays == null) return 1 / 24;
    final span = (maxDays - minDays) < 1 / 24 ? 1 / 24 : (maxDays - minDays);
    final fit = viewWidth / (span + 1);
    if (fit.isNaN || fit.isInfinite || fit <= 0) return 1 / 24;
    return fit;
  }

  static double clampPixels(double pixelsPerDay, Iterable<DateTime> times, double viewWidth) {
    final floor = fitPixelsPerDay(times, viewWidth);
    final hi = maxPixelsPerDay;
    final lo = floor > hi ? hi : floor;
    return pixelsPerDay.clamp(lo, hi).toDouble();
  }
}

/// Wall-clock fields of [time], as days since 1970-01-01. Does not shift zones:
/// pass an already-local value when the instant should be read in local time.
double timeDays(DateTime time) {
  final utc = DateTime.utc(time.year, time.month, time.day, time.hour, time.minute, time.second);
  return utc.difference(DateTime.utc(1970)).inMicroseconds / Duration.microsecondsPerDay;
}

DateTime dateFromTimeDays(double days) {
  final micros = (days * Duration.microsecondsPerDay).round();
  return DateTime.utc(1970).add(Duration(microseconds: micros));
}

TimeBucket bucketFor(DateTime time, TimeResolution resolution) {
  final t = time;
  switch (resolution.unit) {
    case TimeUnit.hour:
    case TimeUnit.hours:
      final step = resolution.step <= 0 ? 1 : resolution.step;
      final startHour = t.hour - _mod(t.hour, step);
      final start = DateTime(t.year, t.month, t.day, startHour);
      final end = start.add(Duration(hours: step));
      final endHour = (startHour + step) % 24;
      final endLabel = endHour == 0 ? '24' : _two(endHour);
      return TimeBucket(
        id: step == 1 ? '${_stamp(start)}T${_two(startHour)}' : '${_stamp(start)}T${_two(startHour)}x$step',
        label: step == 1 ? '${t.month}月${t.day}日 ${_two(startHour)}:00' : '${t.day}日 ${_two(startHour)}–$endLabel',
        centerDays: (timeDays(start) + timeDays(end)) / 2,
      );
    case TimeUnit.day:
      final start = DateTime(t.year, t.month, t.day);
      return TimeBucket(
        id: _stamp(start),
        label: '${t.month}月${t.day}日',
        centerDays: timeDays(start) + 0.5,
      );
    case TimeUnit.days:
      final step = resolution.step <= 0 ? 3 : resolution.step;
      final n = dayNumber(t);
      final startN = n - _mod(n, step);
      final start = dateFromDayNumber(startN);
      final last = dateFromDayNumber(startN + step - 1);
      return TimeBucket(
        id: 'd$step:${_stamp(start)}',
        label: '${start.month}月${start.day}日–${last.month}月${last.day}日',
        centerDays: startN + step / 2,
      );
    case TimeUnit.week:
    case TimeUnit.weeks:
      final step = resolution.unit == TimeUnit.week ? 7 : (resolution.step <= 0 ? 14 : resolution.step);
      final day = DateTime(t.year, t.month, t.day);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      final mondayN = dayNumber(monday);
      final startN = mondayN - _mod(mondayN - _fortnightAnchor, step);
      final start = dateFromDayNumber(startN);
      final last = dateFromDayNumber(startN + step - 1);
      return TimeBucket(
        id: step == 7 ? _stamp(start) : 'w$step:${_stamp(start)}',
        label: '${start.month}月${start.day}日–${last.month}月${last.day}日',
        centerDays: startN + step / 2,
      );
    case TimeUnit.month:
    case TimeUnit.months:
      final step = resolution.unit == TimeUnit.month ? 1 : (resolution.step <= 0 ? 3 : resolution.step);
      final index = t.year * 12 + (t.month - 1);
      final startIndex = index - _mod(index, step);
      final sy = startIndex ~/ 12;
      final sm = _mod(startIndex, 12);
      final start = DateTime(sy, sm + 1, 1);
      final end = DateTime(sy, sm + 1 + step, 1);
      final endIndex = sm + step - 1;
      final ey = sy + endIndex ~/ 12;
      final em = _mod(endIndex, 12);
      final label = step == 1
          ? '${t.year}年${t.month}月'
          : ey == sy
              ? '$sy年${sm + 1}–${em + 1}月'
              : '$sy年${sm + 1}月–$ey年${em + 1}月';
      return TimeBucket(
        id: step == 1 ? '$sy-${_two(sm + 1)}' : 'm$step:$sy-${_two(sm + 1)}',
        label: label,
        centerDays: (timeDays(start) + timeDays(end)) / 2,
      );
    case TimeUnit.year:
      final start = DateTime(t.year, 1, 1);
      final end = DateTime(t.year + 1, 1, 1);
      return TimeBucket(
        id: '${t.year}',
        label: '${t.year}',
        centerDays: (timeDays(start) + timeDays(end)) / 2,
      );
    case TimeUnit.years:
      final span = resolution.step <= 0 ? 3 : resolution.step;
      final startYear = t.year - _mod(t.year, span);
      final start = DateTime(startYear, 1, 1);
      final end = DateTime(startYear + span, 1, 1);
      return TimeBucket(
        id: 'y$span:$startYear',
        label: '$startYear–${startYear + span - 1}',
        centerDays: (timeDays(start) + timeDays(end)) / 2,
      );
  }
}

int get _fortnightAnchor => dayNumber(DateTime(1970, 1, 5));

int _mod(int value, int modulo) {
  if (modulo <= 0) return 0;
  final raw = value % modulo;
  return raw < 0 ? raw + modulo : raw;
}

/// Ticks stay about a thumb apart, aligned to the calendar, whatever the scale.
RulerGeometry rulerFor({
  required double pixelsPerDay,
  required double startDays,
  required double endDays,
}) {
  final ppd = pixelsPerDay <= 0 ? 1.0 : pixelsPerDay;
  final lo = startDays < endDays ? startDays : endDays;
  final hi = startDays < endDays ? endDays : startDays;
  final hourPx = ppd / 24;
  if (hourPx >= 52) return _hours(lo, hi, 1, ppd);
  if (hourPx * 3 >= 52) return _hours(lo, hi, 3, ppd);
  if (hourPx * 6 >= 52) return _hours(lo, hi, 6, ppd);
  if (ppd >= 48) return _days(lo, hi, ppd);
  if (ppd * 7 >= 56) return _weeks(lo, hi);
  if (ppd * 30 >= 56) return _months(lo, hi, ppd);
  if (ppd * 365.2425 >= 64) return _years(lo, hi, 1);
  var span = 3;
  while (ppd * 365.2425 * span < 72 && span < 600) {
    span += 3;
  }
  return _years(lo, hi, span);
}

RulerGeometry _hours(double lo, double hi, int step, double ppd) {
  final ticks = <RulerTick>[];
  final origin = dateFromTimeDays(lo);
  var hour = DateTime.utc(origin.year, origin.month, origin.day, origin.hour);
  var rewind = 0;
  while (hour.hour % step != 0 && rewind < 24) {
    hour = hour.subtract(const Duration(hours: 1));
    rewind++;
  }
  hour = hour.subtract(Duration(hours: step));
  final end = dateFromTimeDays(hi).add(Duration(hours: step + 1));
  var guard = 0;
  while (!hour.isAfter(end) && guard < 500) {
    guard++;
    final midnight = hour.hour == 0;
    ticks.add(RulerTick(
      timeDays(hour),
      midnight ? '${hour.month}月${hour.day}日' : _two(hour.hour),
      major: midnight,
    ));
    final next = hour.add(Duration(hours: step));
    if (!next.isAfter(hour)) break;
    hour = next;
  }
  return RulerGeometry(ticks, _monthBands(lo, hi, ppd));
}

RulerGeometry _days(double lo, double hi, double ppd) {
  final ticks = <RulerTick>[];
  var day = DateTime.utc(dateFromTimeDays(lo).year, dateFromTimeDays(lo).month, dateFromTimeDays(lo).day);
  day = day.subtract(const Duration(days: 1));
  final end = dateFromTimeDays(hi).add(const Duration(days: 2));
  var guard = 0;
  while (day.isBefore(end) && guard < 800) {
    guard++;
    final days = timeDays(day);
    final month = day.day == 1;
    final show = month || ppd >= 90 || (ppd >= 56 && (day.day == 5 || day.day == 10 || day.day == 15 || day.day == 20 || day.day == 25));
    ticks.add(RulerTick(
      days,
      show ? (month ? '${day.year}  ${day.month}月' : '${day.day}') : '',
      major: month,
    ));
    day = day.add(const Duration(days: 1));
  }
  return RulerGeometry(ticks, _monthBands(lo, hi, ppd));
}

RulerGeometry _weeks(double lo, double hi) {
  final ticks = <RulerTick>[];
  final first = dateFromTimeDays(lo);
  final weekday = first.weekday;
  var monday = DateTime.utc(first.year, first.month, first.day).subtract(Duration(days: weekday - 1 + 7));
  final end = dateFromTimeDays(hi).add(const Duration(days: 14));
  var guard = 0;
  while (monday.isBefore(end) && guard < 400) {
    guard++;
    final month = monday.day <= 7;
    ticks.add(RulerTick(
      timeDays(monday),
      month ? '${monday.year}  ${monday.month}月' : '${monday.month}/${monday.day}',
      major: month,
    ));
    monday = monday.add(const Duration(days: 7));
  }
  return RulerGeometry(ticks, _yearBands(lo, hi));
}

RulerGeometry _months(double lo, double hi, double ppd) {
  final ticks = <RulerTick>[];
  final first = dateFromTimeDays(lo);
  var cursor = DateTime.utc(first.year, first.month - 1, 1);
  final end = dateFromTimeDays(hi).add(const Duration(days: 40));
  var guard = 0;
  while (cursor.isBefore(end) && guard < 400) {
    guard++;
    final january = cursor.month == 1;
    ticks.add(RulerTick(
      timeDays(cursor),
      january || ppd * 30 >= 88 ? (january ? '${cursor.year}' : '${cursor.month}月') : '',
      major: january,
    ));
    cursor = DateTime.utc(cursor.year, cursor.month + 1, 1);
  }
  return RulerGeometry(ticks, _yearBands(lo, hi));
}

RulerGeometry _years(double lo, double hi, int span) {
  final ticks = <RulerTick>[];
  final first = dateFromTimeDays(lo).year;
  var year = first - (first % span) - span;
  final last = dateFromTimeDays(hi).year + span;
  var guard = 0;
  while (year <= last && guard < 400) {
    guard++;
    final label = span == 1 ? '$year' : '$year–${year + span - 1}';
    ticks.add(RulerTick(timeDays(DateTime.utc(year)), label, major: true));
    year += span;
  }
  final bands = <ShadeBand>[];
  year = first - (first % (span * 2)) - span * 2;
  guard = 0;
  while (year <= last && guard < 200) {
    guard++;
    if (((year ~/ span) % 2) == 0) {
      final start = timeDays(DateTime.utc(year));
      final end = timeDays(DateTime.utc(year + span));
      bands.add(ShadeBand(start, end - start));
    }
    year += span;
  }
  return RulerGeometry(ticks, bands);
}

List<ShadeBand> _monthBands(double lo, double hi, double ppd) {
  final bands = <ShadeBand>[];
  final first = dateFromTimeDays(lo);
  var cursor = DateTime.utc(first.year, first.month - 1, 1);
  final end = dateFromTimeDays(hi).add(const Duration(days: 32));
  var guard = 0;
  while (cursor.isBefore(end) && guard < 80) {
    guard++;
    if (cursor.month.isEven) {
      final next = DateTime.utc(cursor.year, cursor.month + 1, 1);
      bands.add(ShadeBand(timeDays(cursor), timeDays(next) - timeDays(cursor)));
    }
    cursor = DateTime.utc(cursor.year, cursor.month + 1, 1);
  }
  return bands;
}

List<ShadeBand> _yearBands(double lo, double hi) {
  final bands = <ShadeBand>[];
  final first = dateFromTimeDays(lo).year - 1;
  final last = dateFromTimeDays(hi).year + 1;
  for (var year = first; year <= last; year++) {
    if (year.isEven) {
      final start = timeDays(DateTime.utc(year));
      final end = timeDays(DateTime.utc(year + 1));
      bands.add(ShadeBand(start, end - start));
    }
  }
  return bands;
}

String _two(int value) => value.toString().padLeft(2, '0');

String _stamp(DateTime day) => '${day.year}-${_two(day.month)}-${_two(day.day)}';
