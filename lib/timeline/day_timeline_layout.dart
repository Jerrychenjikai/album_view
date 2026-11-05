import 'dart:ui';

import '../models/media_asset.dart';
import '../models/media_batch.dart';
import 'day_number.dart';
import 'time_resolution.dart';
import 'timeline_metrics.dart';

/// Chronological arrangement. The bucket size follows the horizontal scale.
enum ArrangeMode { time }

class DayTimelineLayout {
  const DayTimelineLayout._();

  static List<MediaBatch> arrange({
    required List<MediaAsset> assets,
    required double trackCrossExtent,
    required double pixelsPerDay,
    required Map<String, int> topIndex,
    ArrangeMode mode = ArrangeMode.time,
    TimeResolution? resolution,
  }) {
    if (mode != ArrangeMode.time) {
      throw UnsupportedError('目前只实现了按时间排列。');
    }
    final scale = pixelsPerDay <= 0 ? 1.0 : pixelsPerDay;
    final active = resolution ?? TimeScale.resolutionFor(scale, trackCrossExtent);

    final groups = <String, List<MediaAsset>>{};
    final buckets = <String, TimeBucket>{};
    for (final asset in assets) {
      final bucket = bucketFor(asset.createdAt.toLocal(), active);
      groups.putIfAbsent(bucket.id, () => <MediaAsset>[]).add(asset);
      buckets[bucket.id] = bucket;
    }

    final keys = groups.keys.toList()..sort((a, b) => buckets[a]!.centerDays.compareTo(buckets[b]!.centerDays));
    final lanes = TimelineMetrics.laneCount(trackCrossExtent);
    final count = keys.length;
    final laneHeight = lanes == 0 ? trackCrossExtent : trackCrossExtent / lanes;
    final batches = <MediaBatch>[];

    for (var index = 0; index < keys.length; index++) {
      final key = keys[index];
      final bucket = buckets[key]!;
      final items = [...groups[key]!]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final x = bucket.centerDays * scale;
      final lane = _laneFor(index, count, lanes);
      final slack = (laneHeight - TimelineMetrics.footprintHeight).clamp(0.0, 10000.0).toDouble();
      final jitter = (unitHash(key) - 0.5) * slack * 0.55;
      final y = (lane + 0.5) * laneHeight + jitter;
      final storedTop = topIndex[key] ?? (items.length - 1);
      final rotation = (unitHash('$key-rot') - 0.5) * 2 * TimelineMetrics.rotationLimit;
      batches.add(
        MediaBatch(
          id: key,
          items: List<MediaAsset>.unmodifiable(items),
          position: Offset(x, y),
          topIndex: storedTop,
          rotation: rotation,
          lane: lane,
          label: bucket.label,
        ),
      );
    }
    return batches;
  }

  /// Few buckets are spread across the whole cross-axis.
  /// Many buckets round-robin so neighbours land in different lanes.
  static int _laneFor(int index, int count, int lanes) {
    if (lanes <= 1) return 0;
    if (count <= 1) return lanes ~/ 2;
    if (count <= lanes) {
      return ((index * (lanes - 1)) / (count - 1)).round();
    }
    return index % lanes;
  }
}