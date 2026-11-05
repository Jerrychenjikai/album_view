import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/media_batch.dart';
import '../state/album_controller.dart';
import '../theme/app_theme.dart';
import '../timeline/resolution_flight.dart';
import '../timeline/time_resolution.dart';
import '../timeline/timeline_metrics.dart';
import 'batch_stack.dart';

class TimelineBoard extends StatefulWidget {
  final AlbumController controller;
  final double trackHeight;
  final double viewWidth;
  final List<MediaBatch> batches;

  const TimelineBoard({
    super.key,
    required this.controller,
    required this.trackHeight,
    required this.viewWidth,
    required this.batches,
  });

  @override
  State<TimelineBoard> createState() => _TimelineBoardState();
}

class _TimelineBoardState extends State<TimelineBoard> with SingleTickerProviderStateMixin {
  final Map<int, Offset> _pointers = {};
  double _travel = 0;
  bool _dragged = false;
  double? _pinchStartDistance;
  double? _pinchStartPpd;
  double? _pinchFocalDay;
  double _panZoomScale = 1;

  late final AnimationController _flightClock;
  ResolutionFlight? _flight;
  String _prevIds = '';
  List<MediaBatch>? _prevBatches;
  double _prevPpd = 1;
  double _prevResolutionDays = 1;
  double _poseT = 0;

  @override
  void initState() {
    super.initState();
    _flightClock = AnimationController(vsync: this)
      ..addListener(() {
        _poseT = _flightClock.value;
        if (mounted) setState(() {});
      })
      ..addStatusListener(_onFlightStatus);
  }

  @override
  void dispose() {
    _flightClock.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TimelineBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = _signature(widget.batches);
    final ppd = widget.controller.viewport.pixelsPerDay;
    final days = widget.controller.resolutionFor(widget.trackHeight).days;
    if (_prevIds.isEmpty) {
      _remember(ids, ppd, days);
      return;
    }
    if (ids != _prevIds) {
      final reduce = MediaQuery.disableAnimationsOf(context);
      final previous = _prevBatches;
      if (!reduce && previous != null && previous.isNotEmpty && widget.batches.isNotEmpty) {
        final from = _flight == null ? previous : _visualBatches(ppd);
        final fromPpd = _flight == null ? _prevPpd : ppd;
        _begin(planResolutionFlight(
          from: from,
          fromPpd: fromPpd,
          to: widget.batches,
          toPpd: ppd,
          coarser: days > _prevResolutionDays + 1e-6,
        ));
      } else {
        _flight = null;
      }
    }
    _remember(ids, ppd, days);
  }

  void _remember(String ids, double ppd, double days) {
    _prevIds = ids;
    _prevBatches = widget.batches;
    _prevPpd = ppd;
    _prevResolutionDays = days;
  }

  String _signature(List<MediaBatch> batches) => batches.map((batch) => batch.id).join('|');

  void _begin(ResolutionFlight flight) {
    _flight = flight;
    _poseT = 0;
    _flightClock.stop();
    _flightClock.duration = Duration(milliseconds: flight.outMs);
    _flightClock.forward(from: 0);
  }

  void _onFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _flight == null) return;
    setState(() => _flight = null);
  }

  List<MediaBatch> _visualBatches(double ppd) {
    final flight = _flight;
    if (flight == null) return _prevBatches ?? widget.batches;
    final cards = flight.merge && _poseT < 0.78 ? flight.outCards : flight.inCards;
    return [
      for (final card in cards)
        card.batch.copyWith(
          position: Offset(
            poseOf(card, _poseT).days * ppd,
            poseOf(card, _poseT).y,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scroll = widget.controller.viewport.scrollX;
    final ppd = widget.controller.viewport.pixelsPerDay;
    final visible = <MediaBatch>[];
    final margin = TimelineMetrics.footprintWidth;
    for (final batch in widget.batches) {
      final screen = batch.position.dx - scroll;
      if (screen >= -margin && screen <= widget.viewWidth + margin) {
        visible.add(batch);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.frameIfNeeded(widget.viewWidth, widget.trackHeight);
      widget.controller.ensureScale(widget.viewWidth);
      widget.controller.pumpThumbnails(visible);
    });

    final visualW = TimelineMetrics.cardWidth + TimelineMetrics.fan * 2;
    final visualH = TimelineMetrics.cardHeight + TimelineMetrics.fan;
    final flight = _flight;
    final under = flight?.inCards ?? const <FlightCard>[];
    final over = flight?.outCards ?? const <FlightCard>[];

    return MouseRegion(
      cursor: _pointers.isEmpty ? SystemMouseCursors.grab : SystemMouseCursors.grabbing,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        onPointerSignal: _onSignal,
        onPointerPanZoomStart: _onPanZoomStart,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DeskPainter(
                  scrollX: scroll,
                  pixelsPerDay: ppd,
                  rulerHeight: TimelineMetrics.rulerHeight,
                ),
              ),
            ),
            if (flight == null)
              for (final batch in visible)
                _placedBatch(
                  key: ValueKey(batch.id),
                  batch: batch,
                  left: batch.position.dx - scroll - visualW / 2,
                  top: TimelineMetrics.rulerHeight + batch.position.dy - visualH / 2,
                  width: visualW,
                  height: visualH,
                  opacity: 1,
                  scale: 1,
                  onTap: () => _handleTap(batch),
                )
            else ...[
              for (final card in under)
                if (_flightOnScreen(card, scroll, ppd, widget.viewWidth))
                  _placedBatch(
                    key: ValueKey(card.batch.id),
                    batch: card.batch,
                    left: poseOf(card, _poseT).days * ppd - scroll - visualW / 2,
                    top: TimelineMetrics.rulerHeight + poseOf(card, _poseT).y - visualH / 2,
                    width: visualW,
                    height: visualH,
                    opacity: poseOf(card, _poseT).opacity,
                    scale: poseOf(card, _poseT).scale,
                    onTap: () {},
                  ),
              for (final card in over)
                if (_flightOnScreen(card, scroll, ppd, widget.viewWidth))
                  _placedBatch(
                    key: ValueKey(card.key),
                    batch: card.batch,
                    left: poseOf(card, _poseT).days * ppd - scroll - visualW / 2,
                    top: TimelineMetrics.rulerHeight + poseOf(card, _poseT).y - visualH / 2,
                    width: visualW,
                    height: visualH,
                    opacity: poseOf(card, _poseT).opacity,
                    scale: poseOf(card, _poseT).scale,
                    onTap: () {},
                  ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _placedBatch({
    required Key key,
    required MediaBatch batch,
    required double left,
    required double top,
    required double width,
    required double height,
    required double opacity,
    required double scale,
    required VoidCallback onTap,
  }) {
    final shown = opacity.clamp(0.0, 1.0).toDouble();
    return Positioned(
      key: key,
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        ignoring: shown < 0.05,
        child: Opacity(
          opacity: shown,
          child: Transform.scale(
            scale: scale,
            child: BatchStack(batch: batch, onTap: onTap),
          ),
        ),
      ),
    );
  }

  bool _flightOnScreen(FlightCard card, double scroll, double ppd, double width) {
    final pose = poseOf(card, _poseT);
    final screen = pose.days * ppd - scroll;
    final margin = TimelineMetrics.footprintWidth * 1.6;
    if (screen < -margin || screen > width + margin) return false;
    return true;
  }

  void _handleTap(MediaBatch batch) {
    if (_dragged || _flight != null) return;
    final box = context.findRenderObject() as RenderBox?;
    Offset? origin;
    if (box != null && box.hasSize) {
      origin = box.localToGlobal(Offset(
        batch.position.dx - widget.controller.viewport.scrollX,
        TimelineMetrics.rulerHeight + batch.position.dy,
      ));
    }
    widget.controller.openBatch(batch, origin: origin);
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _dragged = false;
      _travel = 0;
    }
    if (_pointers.length == 2) _beginPinch();
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _pointers[event.pointer];
    if (previous == null) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _updatePinch();
      _dragged = true;
      return;
    }
    final delta = event.localPosition - previous;
    _travel += delta.distance;
    if (!_dragged && _travel < 8) return;
    _dragged = true;
    widget.controller.panBy(delta.dx, viewWidth: widget.viewWidth);
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    _pinchStartDistance = null;
    _pinchStartPpd = null;
    _pinchFocalDay = null;
  }

  void _beginPinch() {
    final points = _pointers.values.toList();
    if (points.length < 2) return;
    final mid = Offset((points[0].dx + points[1].dx) / 2, (points[0].dy + points[1].dy) / 2);
    final distance = (points[0] - points[1]).distance;
    _pinchStartDistance = distance < 12 ? 12 : distance;
    _pinchStartPpd = widget.controller.viewport.pixelsPerDay;
    _pinchFocalDay = (widget.controller.viewport.scrollX + mid.dx) / widget.controller.viewport.pixelsPerDay;
  }

  void _updatePinch() {
    final points = _pointers.values.toList();
    if (points.length < 2 || _pinchStartDistance == null || _pinchFocalDay == null || _pinchStartPpd == null) {
      return;
    }
    final mid = Offset((points[0].dx + points[1].dx) / 2, (points[0].dy + points[1].dy) / 2);
    final distance = math.max(12.0, (points[0] - points[1]).distance);
    final next = _pinchStartPpd! * distance / _pinchStartDistance!;
    widget.controller.applyViewport(
      pixelsPerDay: next,
      focalDays: _pinchFocalDay!,
      focalScreenX: mid.dx,
      viewWidth: widget.viewWidth,
    );
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    widget.controller.zoomAt(
      focalScreenX: event.localPosition.dx,
      factor: math.exp(-dy * 0.0016),
      viewWidth: widget.viewWidth,
    );
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _panZoomScale = 1;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.panDelta.dx != 0) {
      widget.controller.panBy(event.panDelta.dx, viewWidth: widget.viewWidth);
      _dragged = true;
    }
    if (event.scale <= 0) return;
    final factor = event.scale / _panZoomScale;
    _panZoomScale = event.scale;
    if ((factor - 1).abs() < 0.0008) return;
    widget.controller.zoomAt(
      focalScreenX: event.localPosition.dx,
      factor: factor,
      viewWidth: widget.viewWidth,
    );
    _dragged = true;
  }
}

class _DeskPainter extends CustomPainter {
  final double scrollX;
  final double pixelsPerDay;
  final double rulerHeight;

  const _DeskPainter({
    required this.scrollX,
    required this.pixelsPerDay,
    required this.rulerHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = DeskColors.bg);
    final ppd = pixelsPerDay <= 0 ? 1.0 : pixelsPerDay;
    final start = scrollX / ppd;
    final end = (scrollX + size.width) / ppd;
    final geometry = rulerFor(pixelsPerDay: ppd, startDays: start - 1, endDays: end + 1);

    final shade = Paint()..color = const Color(0x10F3EFE4);
    for (final band in geometry.bands) {
      final x = band.startDays * ppd - scrollX;
      final width = band.spanDays * ppd;
      if (width < 1) continue;
      canvas.drawRect(Rect.fromLTWH(x, rulerHeight, width, size.height - rulerHeight), shade);
    }

    final grid = Paint()
      ..color = const Color(0x223A332C)
      ..strokeWidth = 1;
    for (final tick in geometry.ticks) {
      if (!tick.major && tick.label.isEmpty) continue;
      final x = tick.days * ppd - scrollX;
      if (x < -40 || x > size.width + 40) continue;
      canvas.drawLine(Offset(x, rulerHeight), Offset(x, size.height), grid);
    }

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, rulerHeight), Paint()..color = const Color(0xF21A1612));
    canvas.drawLine(
      Offset(0, rulerHeight - 0.5),
      Offset(size.width, rulerHeight - 0.5),
      Paint()..color = DeskColors.line,
    );

    for (final tick in geometry.ticks) {
      final x = tick.days * ppd - scrollX;
      if (x < -80 || x > size.width + 20) continue;
      canvas.drawLine(
        Offset(x, rulerHeight - (tick.major ? 16 : 8)),
        Offset(x, rulerHeight),
        Paint()
          ..color = tick.major ? DeskColors.amber : DeskColors.line
          ..strokeWidth = tick.major ? 1.4 : 1,
      );
      if (tick.label.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: tick.label,
          style: TextStyle(
            color: tick.major ? DeskColors.paper : DeskColors.muted,
            fontSize: tick.major ? 12 : 11,
            fontWeight: tick.major ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 140);
      painter.paint(canvas, Offset(x + 6, tick.major ? 8 : 18));
      painter.dispose();
    }

    final todayX = timeDays(DateTime.now()) * ppd - scrollX;
    if (todayX >= -20 && todayX <= size.width + 20) {
      canvas.drawLine(
        Offset(todayX, rulerHeight),
        Offset(todayX, size.height),
        Paint()
          ..color = DeskColors.amber.withOpacity(0.85)
          ..strokeWidth = 1.2,
      );
      final tag = TextPainter(
        text: const TextSpan(
          text: '今天',
          style: TextStyle(color: DeskColors.ink, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(todayX - tag.width / 2 - 6, 6, tag.width + 12, 18),
        const Radius.circular(9),
      );
      canvas.drawRRect(rect, Paint()..color = DeskColors.amber);
      tag.paint(canvas, Offset(todayX - tag.width / 2, 8));
      tag.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _DeskPainter oldDelegate) {
    return oldDelegate.scrollX != scrollX ||
        oldDelegate.pixelsPerDay != pixelsPerDay ||
        oldDelegate.rulerHeight != rulerHeight;
  }
}
