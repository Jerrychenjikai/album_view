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

/// Represents a date in the Chinese lunar calendar.
class LunarDate {
  final int year;
  final int month;
  final int day;
  final bool isLeap;

  const LunarDate({
    required this.year,
    required this.month,
    required this.day,
    this.isLeap = false,
  });
}

/// Chinese Lunar Calendar calculation engine (1900–2100).
class LunarCalendar {
  const LunarCalendar._();

  static const int minYear = 1900;
  static const int maxYear = 2100;

  static const List<int> _lunarInfo = [
    0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0, 0x09ad0, 0x055d2,
    0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2, 0x095b0, 0x14977,
    0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570, 0x052f2, 0x04970,
    0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0, 0x1c8d7, 0x0c950,
    0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2, 0x0a950, 0x0b557,
    0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5d0, 0x14573, 0x052d0, 0x0a9a8, 0x0e950, 0x06aa0,
    0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950, 0x05b57, 0x056a0,
    0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540, 0x0b5a0, 0x195a6,
    0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46, 0x0ab60, 0x09570,
    0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60, 0x096d5, 0x092e0,
    0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0, 0x092d0, 0x0cab5,
    0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176, 0x052b0, 0x0a930,
    0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260, 0x0ea65, 0x0d530,
    0x05aa0, 0x076a3, 0x096d0, 0x04bd7, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250, 0x0d520, 0x0dd45,
    0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255, 0x06d20, 0x0ada0,
    0x14b63,
  ];

  static final DateTime _baseDate = DateTime.utc(1900, 1, 31);

  /// Converts a Gregorian date (year, month, day) to a [LunarDate].
  static LunarDate? solarToLunar(int year, int month, int day) {
    if (year < minYear || year > maxYear) return null;
    final solarUtc = DateTime.utc(year, month, day);
    var offset = solarUtc.difference(_baseDate).inDays;
    if (offset < 0) return null;

    var lunarYear = minYear;
    for (var y = minYear; y <= maxYear; y++) {
      final info = _lunarInfo[y - minYear];
      var days = 0;
      for (var m = 1; m <= 12; m++) {
        days += (info & (0x10000 >> m)) != 0 ? 30 : 29;
      }
      final leap = info & 0xf;
      if (leap != 0) {
        days += (info & 0x10000) != 0 ? 30 : 29;
      }
      if (offset < days) {
        lunarYear = y;
        break;
      }
      offset -= days;
    }

    final info = _lunarInfo[lunarYear - minYear];
    final leap = info & 0xf;
    var isLeap = false;
    var lunarMonth = 1;

    for (var m = 1; m <= 12; m++) {
      final days = (info & (0x10000 >> m)) != 0 ? 30 : 29;
      if (offset < days) {
        lunarMonth = m;
        break;
      }
      offset -= days;

      if (leap == m) {
        final leapDays = (info & 0x10000) != 0 ? 30 : 29;
        if (offset < leapDays) {
          lunarMonth = m;
          isLeap = true;
          break;
        }
        offset -= leapDays;
      }
    }

    final lunarDay = offset + 1;
    return LunarDate(
      year: lunarYear,
      month: lunarMonth,
      day: lunarDay,
      isLeap: isLeap,
    );
  }

  /// Converts a lunar date to the corresponding solar [DateTime] (in local date fields).
  static DateTime? lunarToSolar(int lunarYear, int lunarMonth, int lunarDay, {bool isLeap = false}) {
    if (lunarYear < minYear || lunarYear > maxYear) return null;
    var days = 0;
    for (var y = minYear; y < lunarYear; y++) {
      final info = _lunarInfo[y - minYear];
      for (var m = 1; m <= 12; m++) {
        days += (info & (0x10000 >> m)) != 0 ? 30 : 29;
      }
      final leap = info & 0xf;
      if (leap != 0) {
        days += (info & 0x10000) != 0 ? 30 : 29;
      }
    }

    final info = _lunarInfo[lunarYear - minYear];
    final leap = info & 0xf;
    for (var m = 1; m < lunarMonth; m++) {
      days += (info & (0x10000 >> m)) != 0 ? 30 : 29;
      if (leap == m) {
        days += (info & 0x10000) != 0 ? 30 : 29;
      }
    }
    if (isLeap && leap == lunarMonth) {
      days += (info & (0x10000 >> lunarMonth)) != 0 ? 30 : 29;
    }
    days += (lunarDay - 1);
    final targetUtc = _baseDate.add(Duration(days: days));
    return DateTime(targetUtc.year, targetUtc.month, targetUtc.day);
  }
}

/// A holiday based on the Chinese lunar calendar (e.g. 春节、端午节、中秋节).
class LunarHoliday extends Holiday {
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

  /// 1-based lunar month (1..12).
  final int lunarMonth;

  /// 1-based lunar day (1..30).
  final int lunarDay;

  const LunarHoliday({
    required this.id,
    required this.name,
    required this.assetPrefix,
    required this.lunarMonth,
    required this.lunarDay,
    this.assetAliases = const [],
    this.stickerCount = 3,
  });

  @override
  bool matchesDate(DateTime date) {
    final local = date.toLocal();
    final lunar = LunarCalendar.solarToLunar(local.year, local.month, local.day);
    if (lunar == null) return false;
    return !lunar.isLeap && lunar.month == lunarMonth && lunar.day == lunarDay;
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
    for (var year = startYear - 1; year <= endYear + 1; year++) {
      final solarDate = LunarCalendar.lunarToSolar(year, lunarMonth, lunarDay);
      if (solarDate == null) continue;
      final holidayStart = DateTime(solarDate.year, solarDate.month, solarDate.day);
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
    const LunarHoliday(
      id: 'spring_festival',
      name: '农历春节',
      assetPrefix: 'spring_festival',
      assetAliases: ['chunjie', 'cny'],
      lunarMonth: 1,
      lunarDay: 1,
    ),
    const LunarHoliday(
      id: 'dragon_boat',
      name: '端午节',
      assetPrefix: 'dragon_boat',
      assetAliases: ['duanwu'],
      lunarMonth: 5,
      lunarDay: 5,
    ),
    const LunarHoliday(
      id: 'mid_autumn',
      name: '中秋节',
      assetPrefix: 'mid_autumn',
      assetAliases: ['zhongqiu'],
      lunarMonth: 8,
      lunarDay: 15,
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

  /// Probability of displaying a decoration on a holiday photo in batch preview (30%).
  static double previewStickerProbability = 0.30;

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

  /// Computes which assets in [batchItems] should display a holiday decoration in batch preview.
  /// Rule:
  /// - Base probability is 30% for photos taken on a holiday's day.
  /// - If the batch contains photos taken on a holiday's day, guarantees at least one contains a decoration.
  static Map<String, Holiday> decoratedAssetsForBatch(
    List<MediaAsset> batchItems, {
    double? probability,
  }) {
    final prob = probability ?? previewStickerProbability;
    final result = <String, Holiday>{};

    // Group assets by holiday (ignoring non-holiday photos)
    final holidayGroups = <Holiday, List<MediaAsset>>{};
    for (final asset in batchItems) {
      final holiday = findHolidayForDate(asset.createdAt);
      if (holiday != null) {
        holidayGroups.putIfAbsent(holiday, () => []).add(asset);
      }
    }

    for (final entry in holidayGroups.entries) {
      final holiday = entry.key;
      final assets = entry.value;
      if (assets.isEmpty) continue;

      MediaAsset? bestFallbackAsset;
      double minChance = double.infinity;
      var decoratedInGroup = 0;

      for (final asset in assets) {
        final chance = unitHash('${asset.id}-holiday-preview-chance');
        if (chance < minChance) {
          minChance = chance;
          bestFallbackAsset = asset;
        }
        if (chance < prob) {
          result[asset.id] = holiday;
          decoratedInGroup++;
        }
      }

      // Guarantee: if this batch contains photos of this holiday, at least one must have decoration.
      if (decoratedInGroup == 0 && bestFallbackAsset != null) {
        result[bestFallbackAsset.id] = holiday;
      }
    }

    return result;
  }

  /// Checks if [asset] in batch preview should display a holiday decoration.
  /// Rule: Photo must be taken on the holiday's day, with 30% probability.
  /// If [batchItems] is provided, also enforces the guarantee that at least one photo
  /// taken on that holiday in the batch receives a decoration.
  static Holiday? holidayForPreviewAsset(MediaAsset asset, {List<MediaAsset>? batchItems}) {
    if (batchItems != null && batchItems.isNotEmpty) {
      final map = decoratedAssetsForBatch(batchItems);
      return map[asset.id];
    }
    final holiday = findHolidayForDate(asset.createdAt);
    if (holiday == null) return null;

    final chance = unitHash('${asset.id}-holiday-preview-chance');
    if (chance < previewStickerProbability) {
      return holiday;
    }
    return null;
  }
}
