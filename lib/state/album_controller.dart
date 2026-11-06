import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../loaders/image_loader.dart';
import '../models/media_asset.dart';
import '../models/media_batch.dart';
import '../models/media_filter.dart';
import '../timeline/day_timeline_layout.dart';
import '../timeline/time_resolution.dart';
import '../timeline/timeline_metrics.dart';
import '../timeline/timeline_viewport.dart';

enum QuickRange { all, days7, days30, thisYear }

enum IntroPhase { reveal, glide, done }

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
  IntroPhase introPhase = IntroPhase.reveal;
  bool pendingGlide = false;
  bool _userMoved = false;
  String? error;
  String sourceLabel = '';
  double viewWidth = 0;
  double trackExtent = 0;
  Timer? _glide;

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
    _glide?.cancel();
    _glide = null;
    loading = true;
    introPhase = IntroPhase.reveal;
    pendingGlide = false;
    _userMoved = false;
    error = null;
    master = const [];
    _thumbGaveUp.clear();
    _parkOnToday(force: true);
    notifyListeners();
    try {
      final assets = await loader.load(
        onBatch: (batch) {
          if (ticket != _loadTicket || batch.isEmpty) return;
          final next = [...master, ...batch]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
          master = next;
          if (!_userMoved && introPhase == IntroPhase.reveal) _parkOnToday(force: true);
          notifyListeners();
        },
      );
      if (ticket != _loadTicket) return;
      master = assets;
      try {
        sourceLabel = await loader.describeSource();
      } catch (_) {
        sourceLabel = '';
      }
      if (_userMoved || assets.isEmpty) {
        introPhase = IntroPhase.done;
        pendingGlide = false;
        _settleScroll();
      } else {
        pendingGlide = true;
      }
    } catch (error) {
      if (ticket != _loadTicket) return;
      master = const [];
      this.error = error.toString();
      sourceLabel = '';
      introPhase = IntroPhase.done;
      pendingGlide = false;
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
    _takeOver();
    _settleScroll();
    notifyListeners();
  }

  void setKind(MediaKind? value) {
    if (kind == value) return;
    kind = value;
    _takeOver();
    _settleScroll();
    notifyListeners();
  }

  void panBy(double deltaScreenX, {required double viewWidth}) {
    this.viewWidth = viewWidth;
    _takeOver();
    viewport.panBy(deltaScreenX);
    _settleScroll();
    notifyListeners();
  }

  void zoomAt({
    required double focalScreenX,
    required double factor,
    required double viewWidth,
  }) {
    this.viewWidth = viewWidth;
    _takeOver();
    viewport.zoomAt(
      focalScreenX: focalScreenX,
      factor: factor,
      minPixelsPerDay: TimeScale.fitPixelsPerDay(visible.map((asset) => asset.createdAt), viewWidth),
      maxPixelsPerDay: TimeScale.maxPixelsPerDay,
    );
    _settleScroll();
    notifyListeners();
  }

  void ensureScale(double viewWidth) {
    this.viewWidth = viewWidth;
    if (introPhase != IntroPhase.done) return;
    if (viewWidth <= 0 || viewport.pixelsPerDay <= 0) return;
    final next = TimeScale.clampPixels(
      viewport.pixelsPerDay,
      visible.map((asset) => asset.createdAt),
      viewWidth,
    );
    if ((next - viewport.pixelsPerDay).abs() < 0.01) {
      _settleScroll();
      return;
    }
    final focalDays = (viewport.scrollX + viewWidth / 2) / viewport.pixelsPerDay;
    viewport.pixelsPerDay = next;
    viewport.scrollX = focalDays * next - viewWidth / 2;
    _settleScroll();
    notifyListeners();
  }

  void frameIfNeeded(double viewWidth, double trackCrossExtent) {
    this.viewWidth = viewWidth;
    trackExtent = trackCrossExtent;
    if (viewWidth <= 0 || trackCrossExtent <= 0) return;
    if (pendingGlide) {
      pendingGlide = false;
      _startGlide();
      return;
    }
    if (loading || introPhase == IntroPhase.reveal) {
      _parkOnToday(force: true);
      return;
    }
    if (introPhase == IntroPhase.glide) return;
    _settleScroll();
  }

  void revealToday(double viewWidth) {
    this.viewWidth = viewWidth;
    _takeOver();
    _parkOnToday(force: true);
    _settleScroll();
    notifyListeners();
  }

  void applyViewport({
    required double pixelsPerDay,
    required double focalDays,
    required double focalScreenX,
    required double viewWidth,
  }) {
    this.viewWidth = viewWidth;
    _takeOver();
    final next = TimeScale.clampPixels(
      pixelsPerDay,
      visible.map((asset) => asset.createdAt),
      viewWidth,
    );
    viewport.pixelsPerDay = next;
    viewport.scrollX = focalDays * next - focalScreenX;
    _settleScroll();
    notifyListeners();
  }

  /// While nothing has loaded yet, keep today in the middle of the track.
  void _parkOnToday({bool force = false}) {
    if (!force && !loading && master.isNotEmpty) return;
    if (viewWidth <= 0 || viewport.pixelsPerDay <= 0) return;
    final target = timeDays(DateTime.now()) * viewport.pixelsPerDay - viewWidth * 0.5;
    if ((viewport.scrollX - target).abs() < 0.5) return;
    viewport.scrollX = target;
    notifyListeners();
  }

  void _settleScroll() {
    if (introPhase == IntroPhase.glide) return;
    if (loading || introPhase == IntroPhase.reveal || visible.isEmpty) {
      _parkOnToday(force: true);
      return;
    }
    if (viewWidth <= 0) return;
    final next = clampTimelineScroll(
      scrollX: viewport.scrollX,
      pixelsPerDay: viewport.pixelsPerDay,
      viewWidth: viewWidth,
      dayMarks: visible.map((asset) => timeDays(asset.createdAt.toLocal())),
      edgePad: TimelineMetrics.footprintWidth / 2,
    );
    if ((next - viewport.scrollX).abs() < 0.01) return;
    viewport.scrollX = next;
    notifyListeners();
  }

  TimeResolution resolutionFor(double trackCrossExtent) {
    return TimeScale.resolutionFor(viewport.pixelsPerDay, trackCrossExtent);
  }

  Offset? previewOrigin;

  void openBatch(MediaBatch batch, {Offset? origin}) {
    if (batch.items.isEmpty) return;
    previewIds = [for (final item in batch.items) item.id];
    selectedBatchId = batch.id;
    previewOrigin = origin;
    notifyListeners();
    for (final item in batch.items) {
      unawaited(_hydrate(item));
    }
  }

  void closePreview() {
    if (previewIds == null) return;
    previewIds = null;
    previewOrigin = null;
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

  void _takeOver() {
    _userMoved = true;
    _glide?.cancel();
    _glide = null;
    pendingGlide = false;
    if (introPhase != IntroPhase.done) introPhase = IntroPhase.done;
  }

  void _startGlide() {
    _glide?.cancel();
    final width = viewWidth;
    final track = trackExtent;
    if (width <= 0 || track <= 0) {
      introPhase = IntroPhase.done;
      notifyListeners();
      return;
    }
    final batches = layout(track);
    final from = viewport.scrollX;
    final double target;
    if (batches.isEmpty) {
      target = timeDays(DateTime.now()) * viewport.pixelsPerDay - width * 0.5;
    } else {
      target = clampTimelineScroll(
        scrollX: batches.last.position.dx - width * 0.62,
        pixelsPerDay: viewport.pixelsPerDay,
        viewWidth: width,
        dayMarks: visible.map((asset) => timeDays(asset.createdAt.toLocal())),
        edgePad: TimelineMetrics.footprintWidth / 2,
      );
    }
    final reduce = PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;
    if (reduce || (target - from).abs() < 1.5) {
      viewport.scrollX = target;
      introPhase = IntroPhase.done;
      notifyListeners();
      return;
    }
    introPhase = IntroPhase.glide;
    final started = DateTime.now();
    const ms = 920;
    _glide = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (introPhase != IntroPhase.glide) {
        timer.cancel();
        return;
      }
      final raw = (DateTime.now().difference(started).inMilliseconds / ms).clamp(0.0, 1.0);
      final eased = raw < 0.5 ? 2 * raw * raw : 1 - ((-2 * raw + 2) * (-2 * raw + 2)) / 2;
      viewport.scrollX = from + (target - from) * eased;
      if (raw >= 1) {
        timer.cancel();
        _glide = null;
        viewport.scrollX = target;
        introPhase = IntroPhase.done;
        _settleScroll();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _glide?.cancel();
    _loadTicket++;
    super.dispose();
  }
}
