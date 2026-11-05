import 'dart:async';

import 'package:flutter/foundation.dart';

import '../loaders/image_loader.dart';
import '../models/media_asset.dart';
import '../models/media_batch.dart';
import '../models/media_filter.dart';
import '../timeline/day_timeline_layout.dart';
import '../timeline/time_resolution.dart';
import '../timeline/timeline_viewport.dart';

enum QuickRange { all, days7, days30, thisYear }

/// Holds the library, the open time filter, and the infinite-canvas camera.
class AlbumController extends ChangeNotifier {
  AlbumController(this.loader);

  final ImageLoader loader;

  List<MediaAsset> master = const [];
  QuickRange quickRange = QuickRange.all;
  MediaKind? kind;
  final Map<String, int> topIndex = {};
  String? selectedBatchId;
  List<String>? previewIds;
  final TimelineViewport viewport = TimelineViewport();

  bool loading = false;
  String? error;
  String sourceLabel = '';
  bool pendingFrame = false;

  final Set<String> _thumbInFlight = {};
  final Set<String> _thumbGaveUp = {};
  int _loadTicket = 0;

  MediaFilter get filter {
    final now = DateTime.now();
    DateTime? start;
    switch (quickRange) {
      case QuickRange.all:
        start = null;
      case QuickRange.days7:
        start = now.subtract(const Duration(days: 7));
      case QuickRange.days30:
        start = now.subtract(const Duration(days: 30));
      case QuickRange.thisYear:
        start = DateTime(now.year, 1, 1);
    }
    return MediaFilter(
      startInclusive: start,
      kinds: kind == null ? null : {kind!},
    );
  }

  List<MediaAsset> get visible {
    final current = filter;
    return master.where(current.accepts).toList(growable: false);
  }

  List<MediaBatch> layout(double trackCrossExtent) {
    return DayTimelineLayout.arrange(
      assets: visible,
      trackCrossExtent: trackCrossExtent,
      pixelsPerDay: viewport.pixelsPerDay,
      topIndex: topIndex,
    );
  }

  Future<void> reload() async {
    final ticket = ++_loadTicket;
    loading = true;
    error = null;
    _thumbGaveUp.clear();
    notifyListeners();
    try {
      final assets = await loader.load();
      if (ticket != _loadTicket) return;
      master = assets;
      try {
        sourceLabel = await loader.describeSource();
      } catch (_) {
        sourceLabel = '';
      }
      pendingFrame = true;
    } catch (error) {
      if (ticket != _loadTicket) return;
      master = const [];
      this.error = error.toString();
      sourceLabel = '';
    } finally {
      if (ticket == _loadTicket) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setFolder(String path) async {
    await loader.setImagePath(path);
    await reload();
  }

  void setQuickRange(QuickRange value) {
    if (quickRange == value) return;
    quickRange = value;
    notifyListeners();
  }

  void setKind(MediaKind? value) {
    if (kind == value) return;
    kind = value;
    notifyListeners();
  }

  void panBy(double deltaScreenX) {
    viewport.panBy(deltaScreenX);
    notifyListeners();
  }

  void zoomAt({
    required double focalScreenX,
    required double factor,
    required double viewWidth,
  }) {
    viewport.zoomAt(
      focalScreenX: focalScreenX,
      factor: factor,
      minPixelsPerDay: TimeScale.fitPixelsPerDay(visible.map((asset) => asset.createdAt), viewWidth),
      maxPixelsPerDay: TimeScale.maxPixelsPerDay,
    );
    notifyListeners();
  }

  void ensureScale(double viewWidth) {
    if (viewWidth <= 0 || viewport.pixelsPerDay <= 0) return;
    final next = TimeScale.clampPixels(
      viewport.pixelsPerDay,
      visible.map((asset) => asset.createdAt),
      viewWidth,
    );
    if ((next - viewport.pixelsPerDay).abs() < 0.01) return;
    final focalDays = (viewport.scrollX + viewWidth / 2) / viewport.pixelsPerDay;
    viewport.pixelsPerDay = next;
    viewport.scrollX = focalDays * next - viewWidth / 2;
    notifyListeners();
  }

  void frameIfNeeded(double viewWidth, double trackCrossExtent) {
    if (!pendingFrame || viewWidth <= 0 || trackCrossExtent <= 0) return;
    pendingFrame = false;
    final next = TimeScale.clampPixels(
      viewport.pixelsPerDay,
      visible.map((asset) => asset.createdAt),
      viewWidth,
    );
    viewport.pixelsPerDay = next;
    final batches = layout(trackCrossExtent);
    if (batches.isEmpty) {
      final x = timeDays(DateTime.now()) * viewport.pixelsPerDay;
      viewport.scrollX = x - viewWidth * 0.5;
    } else {
      viewport.scrollX = batches.last.position.dx - viewWidth * 0.62;
    }
    notifyListeners();
  }

  void revealToday(double viewWidth) {
    final x = timeDays(DateTime.now()) * viewport.pixelsPerDay;
    viewport.scrollX = x - viewWidth * 0.5;
    notifyListeners();
  }

  void applyViewport({
    required double pixelsPerDay,
    required double focalDays,
    required double focalScreenX,
    required double viewWidth,
  }) {
    final next = TimeScale.clampPixels(
      pixelsPerDay,
      visible.map((asset) => asset.createdAt),
      viewWidth,
    );
    viewport.pixelsPerDay = next;
    viewport.scrollX = focalDays * next - focalScreenX;
    notifyListeners();
  }

  TimeResolution resolutionFor(double trackCrossExtent) {
    return TimeScale.resolutionFor(viewport.pixelsPerDay, trackCrossExtent);
  }

  void openBatch(MediaBatch batch) {
    if (batch.items.isEmpty) return;
    previewIds = [for (final item in batch.items) item.id];
    selectedBatchId = batch.id;
    notifyListeners();
    for (final item in batch.items) {
      unawaited(_hydrate(item));
    }
  }

  void closePreview() {
    if (previewIds == null) return;
    previewIds = null;
    notifyListeners();
  }

  List<MediaAsset> get previewItems {
    final ids = previewIds;
    if (ids == null) return const [];
    final byId = {for (final asset in master) asset.id: asset};
    return [for (final id in ids) if (byId[id] != null) byId[id]!];
  }

  void selectBatch(MediaBatch batch) => openBatch(batch);

  void pumpThumbnails(List<MediaBatch> onScreen) {
    final queue = <MediaAsset>[];
    for (final batch in onScreen) {
      final top = batch.topItem;
      if (top == null || top.hasThumbnail) continue;
      if (_thumbInFlight.contains(top.id) || _thumbGaveUp.contains(top.id)) continue;
      queue.add(top);
      if (queue.length >= 3) break;
    }
    for (final asset in queue) {
      _thumbInFlight.add(asset.id);
      unawaited(_loadThumb(asset));
    }
  }

  Future<void> _loadThumb(MediaAsset asset) async {
    try {
      final updated = await loader.ensureThumbnail(asset);
      if (!updated.hasThumbnail) {
        _thumbGaveUp.add(asset.id);
      } else {
        _replace(updated);
        notifyListeners();
      }
    } catch (_) {
      // A missing preview should not take down the table.
    } finally {
      _thumbInFlight.remove(asset.id);
    }
  }

  Future<void> _hydrate(MediaAsset asset) async {
    try {
      var next = asset;
      if (!next.hasThumbnail) {
        next = await loader.ensureThumbnail(next);
        _replace(next);
      }
      next = await loader.ensureDetails(next);
      _replace(next);
      notifyListeners();
    } catch (_) {}
  }

  void _replace(MediaAsset asset) {
    final index = master.indexWhere((item) => item.id == asset.id);
    if (index < 0) return;
    final copy = [...master];
    copy[index] = asset;
    master = copy;
  }
}
