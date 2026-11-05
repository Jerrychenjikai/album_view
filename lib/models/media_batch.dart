import 'dart:ui';

import 'media_asset.dart';

/// A stack of media sitting on the infinite light table.
///
/// A batch may hold a single item. Items share one time bucket.
class MediaBatch {
  final String id;
  final List<MediaAsset> items;

  /// Center of the stack, in infinite-canvas pixels.
  /// x grows with time; y is the cross-axis (the finite "width" of the track).
  final Offset position;

  /// Index into [items] of the print currently on top.
  final int topIndex;

  /// Stable tilt, radians. Kept small so neighbours do not collide.
  final double rotation;

  /// Cross-axis lane assigned by the layout. Useful for hit-testing and tests.
  final int lane;

  /// Short calendar label for the whole bucket ("3月2日", "2024", "2016–2018").
  final String label;

  const MediaBatch({
    required this.id,
    required this.items,
    required this.position,
    required this.topIndex,
    this.rotation = 0,
    this.lane = 0,
    this.label = '',
  });

  MediaAsset? get topItem {
    if (items.isEmpty) return null;
    final index = positiveMod(topIndex, items.length);
    return items[index];
  }

  int get resolvedTopIndex {
    if (items.isEmpty) return 0;
    return positiveMod(topIndex, items.length);
  }

  DateTime get day {
    if (items.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    final local = items.first.createdAt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  MediaBatch copyWith({
    List<MediaAsset>? items,
    Offset? position,
    int? topIndex,
    double? rotation,
    int? lane,
    String? label,
  }) {
    return MediaBatch(
      id: id,
      items: items ?? this.items,
      position: position ?? this.position,
      topIndex: topIndex ?? this.topIndex,
      rotation: rotation ?? this.rotation,
      lane: lane ?? this.lane,
      label: label ?? this.label,
    );
  }
}

int positiveMod(int value, int modulo) {
  if (modulo <= 0) return 0;
  final raw = value % modulo;
  return raw < 0 ? raw + modulo : raw;
}
