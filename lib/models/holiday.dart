import '../timeline/day_number.dart';
import '../timeline/time_resolution.dart';
import 'media_asset.dart';
import 'media_batch.dart';

/// Base class for holidays to display festive sticker decorations.
/// Designed for easy extension to support more holidays.
abstract class Holiday {
  const Holiday();

  /// Unique identifier, e.g. 'new_year', 'halloween', 'christmas'.
  String get id;

  /// Human-readable display name, e.g. '阳历新年', '万圣节', '圣诞节'.
  String get name;

  /// Asset name prefix in `assets/holidays/<assetPrefix>_<1..3>.png`.
  String get assetPrefix;

  /// Optional alternative prefixes if files are named differently.
  List<String> get assetAliases => const [];

  /// Number of sticker variants available for this holiday (defaults to 3).
  int get stickerCount => 3;

  /// Whether the specific calendar date (in local time) falls on this holiday.
  bool matchesDate(DateTime date);

  /// Whether the time interval [start, end] overlaps with this holiday's day.
  bool overlapsRange(DateTime start, DateTime end);

  /// Returns the asset path for variant [index] (1-based, 1..stickerCount).
  String assetPath(int index) => 'assets/holidays/${assetPrefix}_$index.png';

  /// Stably picks a variant index 1..stickerCount given a seed string.
  int variantForSeed(String seed) {
    if (stickerCount <= 1) return 1;
    final hash = unitHash('$seed-$id-variant');
    return 1 + (hash * stickerCount).floor().clamp(0, stickerCount - 1);
  }
}

/// A holiday that falls on a fixed month and day of the Gregorian calendar.
class FixedDateHoliday extends Holiday {
  @override
  final String id;
  @override
  final String name;
  @override
  final String assetPrefix;
  @override
  final List<String> assetAliases;
  @override
  final int stickerCount;

  /// 1-based month (1..12).
  final int month;

  /// 1-based day (1..31).
  final int day;

  const FixedDateHoliday({
    required this.id,
    required this.name,
    required this.assetPrefix,
    required this.month,
    required this.day,
    this.assetAliases = const [],
    this.stickerCount = 3,
  });

  @override
  bool matchesDate(DateTime date) {
    final local = date.toLocal();
    return local.month == month && local.day == day;
  }

  @override
  bool overlapsRange(DateTime start, DateTime end) {
    final s = start.toLocal();
    final e = end.toLocal();
    if (!e.isAfter(s)) {
      return matchesDate(s);
    }
    final startYear = s.year;
    final endYear = e.year;
    for (var year = startYear; year <= endYear; year++) {
      final holidayStart = DateTime(year, month, day);
      final holidayEnd = holidayStart.add(const Duration(days: 1));
      if (s.isBefore(holidayEnd) && holidayStart.isBefore(e)) {
        return true;
      }
    }
    return false;
  }
}

/// Registry and helpers for holiday decorations across the timeline and preview.
class HolidayRegistry {
  /// The active holidays. Add new holidays here to extend support.
  static final List<Holiday> holidays = [
    const FixedDateHoliday(
      id: 'new_year',
      name: '阳历新年',
      assetPrefix: 'new_year',
      assetAliases: ['newyear'],
      month: 1,
      day: 1,
    ),
    const FixedDateHoliday(
      id: 'halloween',
      name: '万圣节',
      assetPrefix: 'halloween',
      month: 10,
      day: 31,
    ),
    const FixedDateHoliday(
      id: 'christmas',
      name: '圣诞节',
      assetPrefix: 'christmas',
      month: 12,
      day: 25,
    ),
  ];

  /// Probability of displaying a decoration on a holiday photo in batch preview (20%).
  static double previewStickerProbability = 0.20;

  /// Checks whether [resolution] is less than or equal to 1 week (<= 7 days).
  static bool isResolutionEligible(TimeResolution resolution) {
    return resolution.days <= TimeResolution.week.days + 1e-6;
  }

  /// Finds a holiday matching the exact day of [date].
  static Holiday? findHolidayForDate(DateTime date) {
    for (final holiday in holidays) {
      if (holiday.matchesDate(date)) return holiday;
    }
    return null;
  }

  /// Finds a holiday overlapping the interval [start, end].
  static Holiday? findHolidayForRange(DateTime start, DateTime end) {
    for (final holiday in holidays) {
      if (holiday.overlapsRange(start, end)) return holiday;
    }
    return null;
  }

  /// Checks if [batch] should display a holiday decoration on the timeline.
  /// Rule: Current resolution must be <= 1 week, and the batch's time range
  /// must overlap with the holiday's day.
  static Holiday? findHolidayForBatch(MediaBatch batch, TimeResolution resolution) {
    if (!isResolutionEligible(resolution)) return null;

    final start = batch.startTime;
    final end = batch.endTime;
    final match = findHolidayForRange(start, end);
    if (match != null) return match;

    // Check individual items if present
    for (final item in batch.items) {
      final itemMatch = findHolidayForDate(item.createdAt);
      if (itemMatch != null) return itemMatch;
    }
    return null;
  }

  /// Checks if [asset] in batch preview should display a holiday decoration.
  /// Rule: Photo must be taken on the holiday's day, with 20% probability.
  static Holiday? holidayForPreviewAsset(MediaAsset asset) {
    final holiday = findHolidayForDate(asset.createdAt);
    if (holiday == null) return null;

    final chance = unitHash('${asset.id}-holiday-preview-chance');
    if (chance < previewStickerProbability) {
      return holiday;
    }
    return null;
  }
}
