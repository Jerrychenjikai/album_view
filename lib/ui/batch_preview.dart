import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../theme/app_theme.dart';
import '../timeline/day_number.dart';

/// Blurred light table, with one batch laid out in as many rows as the track.
class BatchPreview extends StatefulWidget {
  final List<MediaAsset> items;
  final int rows;
  final VoidCallback onClose;

  const BatchPreview({
    super.key,
    required this.items,
    required this.rows,
    required this.onClose,
  });

  @override
  State<BatchPreview> createState() => _BatchPreviewState();
}

class _BatchPreviewState extends State<BatchPreview> {
  final ScrollController _scroll = ScrollController();
  final Map<String, GlobalKey> _keys = {};
  final Map<int, Offset> _pointers = {};
  final Set<String> _flipped = {};

  double _travel = 0;
  bool _dragged = false;
  String? _zoomId;
  double _scale = 1;
  Offset _pan = Offset.zero;
  _Pinch? _pinch;
  Size _card = const Size(180, 220);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final rows = math.max(1, widget.rows);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 16.0;
        final pad = 36.0;
        final cardH = ((constraints.maxHeight - pad - gap * (rows - 1)) / rows).clamp(120.0, 440.0);
        final cardW = cardH * 142 / 172;
        _card = Size(cardW, cardH);
        final columns = <List<MediaAsset>>[];
        for (var i = 0; i < widget.items.length; i += rows) {
          final end = math.min(i + rows, widget.items.length);
          columns.add(widget.items.sublist(i, end));
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerSignal: _signal,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: ColoredBox(
                color: const Color(0xB31A1612),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ListView(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                        children: [
                          for (final column in columns)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: SizedBox(
                                height: math.max(120, constraints.maxHeight - 36),
                                child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < column.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 16),
                                    SizedBox(
                                      key: _keyFor(column[i].id),
                                      width: cardW,
                                      height: cardH,
                                      child: _Polaroid(
                                        asset: column[i],
                                        flipped: _flipped.contains(column[i].id),
                                        caption: _frontCaption(column[i]),
                                      ),
                                    ),
                                  ],
                                ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_zoomId != null) _zoomed(cardW, cardH),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 14,
                      child: IgnorePointer(
                        child: Text(
                          '点一张翻到背面    双指或滚轮放大    点空白返回',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: DeskColors.muted, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _zoomed(double cardW, double cardH) {
    MediaAsset? asset;
    for (final item in widget.items) {
      if (item.id == _zoomId) asset = item;
    }
    if (asset == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: _pan,
          child: Transform.scale(
            scale: _scale,
            child: SizedBox(
              width: cardW,
              height: cardH,
              child: _Polaroid(
                asset: asset,
                flipped: _flipped.contains(asset.id),
                caption: _frontCaption(asset),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _frontCaption(MediaAsset asset) {
    final local = asset.createdAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.month}月${local.day}日  $hh:$mm';
  }

  String? _hit(Offset global) {
    if (_insideZoom(global)) return _zoomId;
    for (final item in widget.items.reversed) {
      final box = _keys[item.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final local = box.globalToLocal(global);
      if (local.dx >= 0 && local.dy >= 0 && local.dx <= box.size.width && local.dy <= box.size.height) {
        return item.id;
      }
    }
    return null;
  }

  bool _insideZoom(Offset global) {
    if (_zoomId == null || _scale <= 1) return false;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final local = box.globalToLocal(global);
    final center = box.size.center(Offset.zero) + _pan;
    final rect = Rect.fromCenter(center: center, width: _card.width * _scale, height: _card.height * _scale);
    return rect.contains(local);
  }

  void _down(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 1) {
      _dragged = false;
      _travel = 0;
      _pinch = null;
    }
    if (_pointers.length == 2) {
      final points = _pointers.values.toList();
      final dist = math.max(12.0, (points[0] - points[1]).distance);
      final id = _hit(points[0]) ?? _hit(points[1]);
      if (id != null) {
        _pinch = _Pinch(id: id, dist: dist, scale: _zoomId == id ? _scale : 1, pan: _zoomId == id ? _pan : Offset.zero);
        setState(() => _zoomId = id);
      }
    }
  }

  void _move(PointerMoveEvent event) {
    final previous = _pointers[event.pointer];
    if (previous == null) return;
    _pointers[event.pointer] = event.position;
    final delta = event.position - previous;
    _travel += delta.distance;
    if (_pointers.length >= 2 && _pinch != null) {
      final points = _pointers.values.toList();
      final dist = math.max(12.0, (points[0] - points[1]).distance);
      final scale = (_pinch!.scale * dist / _pinch!.dist).clamp(1.0, 5.0);
      setState(() {
        _zoomId = _pinch!.id;
        _scale = scale;
        _pan = _pinch!.pan;
        if (_scale <= 1.02) {
          _scale = 1;
          _pan = Offset.zero;
        }
      });
      _dragged = true;
      return;
    }
    if (!_dragged && _travel < 8) return;
    _dragged = true;
    if (_zoomId != null && _scale > 1 && _insideZoom(previous)) {
      setState(() => _pan += delta);
      return;
    }
    if (!_scroll.hasClients) return;
    final next = (_scroll.offset - delta.dx).clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.jumpTo(next);
  }

  void _up(PointerEvent event) {
    final wasDrag = _dragged || _travel >= 8;
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _pinch = null;
    if (wasDrag || _pointers.isNotEmpty) return;
    final id = _hit(event.position);
    if (id == null) {
      widget.onClose();
      return;
    }
    if (_zoomId == id && _scale > 1) return;
    setState(() {
      if (_flipped.contains(id)) {
        _flipped.remove(id);
      } else {
        _flipped.add(id);
      }
    });
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final id = _hit(event.position);
    if (id == null) {
      if (!_scroll.hasClients) return;
      final next = (_scroll.offset + event.scrollDelta.dy).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.jumpTo(next);
      return;
    }
    final base = _zoomId == id ? _scale : 1.0;
    final scale = (base * math.exp(-event.scrollDelta.dy * 0.0016)).clamp(1.0, 5.0);
    setState(() {
      _zoomId = scale <= 1.02 ? null : id;
      _scale = scale <= 1.02 ? 1 : scale;
      if (_scale == 1) _pan = Offset.zero;
    });
  }
}

class _Pinch {
  final String id;
  final double dist;
  final double scale;
  final Offset pan;
  const _Pinch({required this.id, required this.dist, required this.scale, required this.pan});
}

class _Polaroid extends StatelessWidget {
  final MediaAsset asset;
  final bool flipped;
  final String caption;

  const _Polaroid({required this.asset, required this.flipped, required this.caption});

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return _Flip(
      flipped: flipped,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 520),
      front: _Face(asset: asset, caption: caption),
      back: _Back(asset: asset),
    );
  }
}

class _Flip extends StatefulWidget {
  final bool flipped;
  final Duration duration;
  final Widget front;
  final Widget back;

  const _Flip({
    required this.flipped,
    required this.duration,
    required this.front,
    required this.back,
  });

  @override
  State<_Flip> createState() => _FlipState();
}

class _FlipState extends State<_Flip> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);

  @override
  void didUpdateWidget(_Flip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (widget.flipped == oldWidget.flipped) return;
    if (widget.flipped) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final angle = _controller.value * math.pi;
        final showBack = angle >= math.pi / 2;
        final face = showBack
            ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: widget.back)
            : widget.front;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: face,
        );
      },
    );
  }
}

class _Face extends StatelessWidget {
  final MediaAsset asset;
  final String caption;

  const _Face({required this.asset, required this.caption});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DeskColors.paper,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 22, offset: Offset(0, 12))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          children: [
            Expanded(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Still(asset: asset),
                    if (asset.kind == MediaKind.video)
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          margin: const EdgeInsets.all(6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          color: const Color(0xCC1C1814),
                          child: Text(
                            asset.durationLabel.isEmpty ? '视频' : asset.durationLabel,
                            style: const TextStyle(color: DeskColors.paper, fontSize: 11),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 16,
              width: double.infinity,
              child: Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: DeskColors.ink, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Back extends StatelessWidget {
  final MediaAsset asset;
  const _Back({required this.asset});

  @override
  Widget build(BuildContext context) {
    final local = asset.createdAt.toLocal();
    final stamp =
        '${local.year}年${local.month}月${local.day}日  ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final lines = <String>[
      stamp,
      if (asset.kind == MediaKind.video) '视频  ${asset.durationLabel.isEmpty ? '' : asset.durationLabel}'.trim(),
      asset.camera.bodyLabel,
      asset.camera.lensLabel,
      asset.camera.exposureLabel,
      asset.resolutionLabel,
      asset.gps?.label ?? '没有位置',
      asset.fileName,
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F1E4),
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 22, offset: Offset(0, 12))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == 0 ? 12 : 6),
                child: Text(
                  lines[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: i == lines.length - 1 ? DeskColors.muted : DeskColors.ink,
                    fontSize: i == 0 ? 16 : 13,
                    height: 1.35,
                    fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Still extends StatelessWidget {
  final MediaAsset asset;
  const _Still({required this.asset});

  @override
  Widget build(BuildContext context) {
    final bytes = asset.thumbnailBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
    }
    final path = asset.thumbnailPath;
    if (path != null && path.isNotEmpty) {
      return Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true);
    }
    final hue = (unitHash(asset.id) * 40 + 18);
    final wash = HSLColor.fromAHSL(1, hue, 0.28, 0.42).toColor();
    final deep = HSLColor.fromAHSL(1, hue + 12, 0.22, 0.24).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [wash, deep]),
      ),
    );
  }
}
