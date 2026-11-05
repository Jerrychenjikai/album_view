/// Calendar-day index that ignores DST. 1970-01-01 is 0.
int dayNumber(DateTime date) {
  final utc = DateTime.utc(date.year, date.month, date.day);
  return utc.difference(DateTime.utc(1970, 1, 1)).inDays;
}

DateTime dateFromDayNumber(int day) {
  return DateTime.utc(1970, 1, 1).add(Duration(days: day));
}

DateTime localDay(DateTime time) {
  final local = time.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String dayKey(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Stable 0–1 value. Not cryptographic; only for layout jitter.
double unitHash(String seed) {
  var hash = 2166136261;
  for (final code in seed.codeUnits) {
    hash ^= code;
    hash = (hash * 16777619) & 0xFFFFFFFF;
  }
  return (hash & 0xFFFFFF) / 0xFFFFFF;
}
