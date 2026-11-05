import 'media_asset.dart';

/// Source-side and in-memory filter shared by every platform loader.
///
/// A null bound means that side of the span is open. [endInclusive] is
/// inclusive, so a single calendar day can be expressed as
/// start = that day 00:00 and end = that day 23:59:59.999.
class MediaFilter {
  final DateTime? startInclusive;
  final DateTime? endInclusive;
  final Set<MediaKind>? kinds;
  final bool requireGps;
  final String? albumContains;
  final String? pathContains;

  const MediaFilter({
    this.startInclusive,
    this.endInclusive,
    this.kinds,
    this.requireGps = false,
    this.albumContains,
    this.pathContains,
  });

  static const empty = MediaFilter();

  bool get hasDateSpan => startInclusive != null || endInclusive != null;

  bool accepts(MediaAsset asset) {
    final taken = asset.createdAt;
    final start = startInclusive;
    if (start != null && taken.isBefore(start)) return false;
    final end = endInclusive;
    if (end != null && taken.isAfter(end)) return false;

    final allowed = kinds;
    if (allowed != null && allowed.isNotEmpty && !allowed.contains(asset.kind)) {
      return false;
    }
    if (requireGps && asset.gps == null) return false;

    final albumNeedle = albumContains?.trim().toLowerCase();
    if (albumNeedle != null && albumNeedle.isNotEmpty) {
      final album = (asset.albumName ?? '').toLowerCase();
      if (!album.contains(albumNeedle)) return false;
    }

    final pathNeedle = pathContains?.trim().toLowerCase();
    if (pathNeedle != null && pathNeedle.isNotEmpty) {
      final path = asset.filePath.toLowerCase();
      if (!path.contains(pathNeedle)) return false;
    }
    return true;
  }

  MediaFilter copyWith({
    DateTime? startInclusive,
    DateTime? endInclusive,
    Set<MediaKind>? kinds,
    bool? requireGps,
    String? albumContains,
    String? pathContains,
    bool clearStart = false,
    bool clearEnd = false,
    bool clearKinds = false,
    bool clearAlbum = false,
    bool clearPath = false,
  }) {
    return MediaFilter(
      startInclusive: clearStart ? null : (startInclusive ?? this.startInclusive),
      endInclusive: clearEnd ? null : (endInclusive ?? this.endInclusive),
      kinds: clearKinds ? null : (kinds ?? this.kinds),
      requireGps: requireGps ?? this.requireGps,
      albumContains: clearAlbum ? null : (albumContains ?? this.albumContains),
      pathContains: clearPath ? null : (pathContains ?? this.pathContains),
    );
  }
}
