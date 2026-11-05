import 'dart:async';
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
  final Offset? originGlobal;
  final Future<String?> Function(MediaAsset asset)? resolveOriginal;
  final Future<void> Function(MediaAsset asset)? onReveal;
  final String locateLabel;
  final VoidCallback onClose;

  const BatchPreview({
    super.key,
    required this.items,
    required this.rows,
    required this.onClose,
    this.originGlobal,
    this.resolveOriginal,
    this.onReveal,
    this.locateLabel = '在文件夹中显示',
  });

  @override
  State<BatchPreview> createState() => _BatchPreviewState();
}

class _BatchPreviewState extends State<BatchPreview> with SingleTickerProviderStateMixin {
  final Map<String, GlobalKey> _keys = {};
  final Map<String, GlobalKey> _locateKeys = {};
  final Map<int, Offset> _pointers = {};
  final Set<String> _flipped = {};

  double _travel = 0;
  bool _dragged = false;
  String? _zoomId;
  double _scale = 1;
  Offset _pan = Offset.zero;
  _Pinch? _pinch;
  Size _card = const Size(180, 220);
  double _offset = 0;
  double _maxOffset = 0;
  double _zoomOpacity = 0;
  Timer? _zoomDismiss;
  Timer? _zoomIdle;
  late final AnimationController _spread;
  bool _closing = false;
  String? _originFor;
  String? _originPath;
  int _originTicket = 0;

  @override
  void initState() {
    super.initState();
    _spread = AnimationController(vsync: this, duration: const Duration(milliseconds: 560))
      ..addListener(() {
        if (mounted) setState(() {});
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _spread.value = 1;
      } else {
        _spread.forward();
      }
    });
  }

  @override
  void dispose() {
    _zoomDismiss?.cancel();
    _zoomIdle?.cancel();
    _spread.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  GlobalKey _locateKey(String id) => _locateKeys.putIfAbsent(id, GlobalKey.new);

  void _armOriginal(String? id) {
    if (id == null || id == _originFor) return;
    _originFor = id;
    _originPath = null;
    MediaAsset? asset;
    for (final item in widget.items) {
      if (item.id == id) asset = item;
    }
    if (asset == null) return;
    final direct = asset.filePath;
    if (direct.isNotEmpty && File(direct).existsSync()) {
      _originPath = direct;
      return;
    }
    final resolve = widget.resolveOriginal;
    if (resolve == null) return;
    final ticket = ++_originTicket;
    resolve(asset).then((found) {
      if (!mounted || ticket != _originTicket || _zoomId != id) return;
      setState(() => _originPath = found);
    });
  }

  Offset _localOrigin(BoxConstraints constraints) {
    final global = widget.originGlobal;
    final box = context.findRenderObject() as RenderBox?;
    if (global == null || box == null || !box.hasSize) {
      return Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
    }
    return box.globalToLocal(global);
  }

  bool _showCard(int index, int rows, double stride, double cardW, double offset, double width, double t) {
    final col = index ~/ rows;
    final x = 28 + col * stride + cardW / 2 - offset;
    final onScreen = x > -cardW * 1.4 && x < width + cardW * 1.4;
    if (onScreen) return true;
    return t < 0.98 && index < rows * 6;
  }

  Widget _placedCard({
    required int index,
    required int rows,
    required double stride,
    required double cardW,
    required double cardH,
    required double gap,
    required double gridH,
    required double offset,
    required Offset origin,
    required double t,
    required BoxConstraints constraints,
  }) {
    final asset = widget.items[index];
    final col = index ~/ rows;
    final row = index % rows;
    final target = Offset(
      28 + col * stride + cardW / 2 - offset,
      (constraints.maxHeight - gridH) / 2 + row * (cardH + gap) + cardH / 2,
    );
    final depth = math.min(3, math.max(0, widget.items.length - 1 - index));
    final fan = Offset(depth == 0 ? 0 : -depth * 7.0, depth * 5.0);
    final center = Offset.lerp(origin + fan, target, t)!;
    final w = _lerp(142, cardW, t);
    final h = _lerp(172, cardH, t);
    final hidden = _zoomId == asset.id && _zoomOpacity > 0.35;
    // Invisible at the first moment so the new cards can mount, then fade in.
    // On the way out, opacity is already 0 before the overlay is removed.
    final fade = hidden ? 0.0 : ((t - 0.02) / 0.4).clamp(0.0, 1.0).toDouble();
    return Positioned(
      left: center.dx - w / 2,
      top: center.dy - h / 2,
      width: w,
      height: h,
      child: IgnorePointer(
        ignoring: fade < 0.04,
        child: Opacity(
          opacity: fade,
          child: SizedBox(
            key: _keyFor(asset.id),
            width: w,
            height: h,
            child: _Polaroid(
              asset: asset,
              flipped: _flipped.contains(asset.id),
              caption: _frontCaption(asset),
              locateLabel: widget.locateLabel,
              locateKey: _locateKey(asset.id),
            ),
          ),
        ),
      ),
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  void _keepZoom() {
    _zoomIdle?.cancel();
    _zoomDismiss?.cancel();
  }

  void _armZoomEnd() {
    _zoomIdle?.cancel();
    _zoomIdle = Timer(const Duration(milliseconds: 140), _dismissZoom);
  }

  void _dismissZoom() {
    if (_zoomId == null) return;
    setState(() => _zoomOpacity = 0);
    _zoomDismiss?.cancel();
    _zoomDismiss = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _zoomId = null;
        _scale = 1;
        _pan = Offset.zero;
        _zoomOpacity = 0;
      });
    });
  }

  void _requestClose() {
    if (_closing) return;
    _closing = true;
    _zoomIdle?.cancel();
    _zoomDismiss?.cancel();
    if (MediaQuery.disableAnimationsOf(context) || _spread.value <= 0.02) {
      widget.onClose();
      return;
    }
    _spread.reverse().whenComplete(() {
      if (mounted) widget.onClose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = math.max(1, widget.rows);
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 16.0;
        final cardH = ((constraints.maxHeight - 36 - gap * (rows - 1)) / rows).clamp(120.0, 440.0).toDouble();
        final cardW = cardH * 142 / 172;
        _card = Size(cardW, cardH);
        final stride = cardW + 20;
        final columnCount = (widget.items.length / rows).ceil();
        final gridH = rows * cardH + (rows - 1) * gap;
        _maxOffset = math.max(0.0, 36 + columnCount * stride - constraints.maxWidth);
        final offset = _offset.clamp(0.0, _maxOffset);
        final t = Curves.easeOutCubic.transform(_spread.value.clamp(0.0, 1.0));
        final origin = _localOrigin(constraints);
        final veil = (179 * t).round().clamp(0, 255);

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _up,
          onPointerSignal: _signal,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18 * t, sigmaY: 18 * t),
              child: ColoredBox(
                color: Color.fromARGB(veil, 0x1A, 0x16, 0x12),
                child: Stack(
                  children: [
                    for (var index = 0; index < widget.items.length; index++)
                      if (_showCard(index, rows, stride, cardW, offset, constraints.maxWidth, t))
                        _placedCard(
                          index: index,
                          rows: rows,
                          stride: stride,
                          cardW: cardW,
                          cardH: cardH,
                          gap: gap,
                          gridH: gridH,
                          offset: offset,
                          origin: origin,
                          t: t,
                          constraints: constraints,
                        ),
                    if (_zoomId != null)
                      AnimatedOpacity(
                        opacity: _zoomOpacity,
                        duration: const Duration(milliseconds: 160),
                        child: _zoomed(cardW, cardH),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 14,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: t,
                          child: const Text(
                            '点一张翻到背面    双指或滚轮看原图    点空白返回',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: DeskColors.muted, fontSize: 12),
                          ),
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
              child: _OriginalPhoto(asset: asset, path: _originFor == asset.id ? _originPath : null),
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
      if (_spread.value < 0.98) return;
      final points = _pointers.values.toList();
      final dist = math.max(12.0, (points[0] - points[1]).distance);
      final id = _hit(points[0]) ?? _hit(points[1]);
      if (id != null) {
        _keepZoom();
        _pinch = _Pinch(id: id, dist: dist, scale: _zoomId == id ? _scale : 1, pan: _zoomId == id ? _pan : Offset.zero);
        _armOriginal(id);
        setState(() {
          _zoomId = id;
          _zoomOpacity = 1;
        });
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
      _keepZoom();
      _armOriginal(_pinch!.id);
      setState(() {
        _zoomId = _pinch!.id;
        _scale = scale <= 1.02 ? 1 : scale;
        _pan = _pinch!.pan;
        _zoomOpacity = scale <= 1.02 ? 0 : 1;
        if (_scale <= 1.02) {
          _scale = 1;
          _pan = Offset.zero;
          _zoomId = null;
        }
      });
      _dragged = true;
      return;
    }
    if (!_dragged && _travel < 8) return;
    _dragged = true;
    if (_zoomId != null && _zoomOpacity > 0.4 && _scale > 1 && _insideZoom(previous)) {
      setState(() => _pan += delta);
      return;
    }
    setState(() {
      _offset = (_offset - delta.dx).clamp(0.0, _maxOffset);
    });
  }

  void _up(PointerEvent event) {
    final endedPinch = _pinch != null;
    final wasDrag = _dragged || _travel >= 8;
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _pinch = null;
    if (endedPinch && _pointers.length < 2 && _zoomId != null && _scale > 1) _armZoomEnd();
    if (_spread.value < 0.98) return;
    if (wasDrag || _pointers.isNotEmpty) return;
    final located = _locateOwner(event.position);
    if (located != null) {
      final reveal = widget.onReveal;
      if (reveal != null) {
        MediaAsset? asset;
        for (final item in widget.items) {
          if (item.id == located) asset = item;
        }
        if (asset != null) reveal(asset);
      }
      return;
    }
    final id = _hit(event.position);
    if (id == null) {
      _requestClose();
      return;
    }
    if (_zoomId == id && _scale > 1 && _zoomOpacity > 0.4) return;
    setState(() {
      if (_flipped.contains(id)) {
        _flipped.remove(id);
      } else {
        _flipped.add(id);
      }
    });
  }

  String? _locateOwner(Offset global) {
    for (final entry in _locateKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final local = box.globalToLocal(global);
      if (local.dx >= 0 && local.dy >= 0 && local.dx <= box.size.width && local.dy <= box.size.height) {
        return entry.key;
      }
    }
    return null;
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_spread.value < 0.98) return;
    final id = _hit(event.position);
    if (id == null) {
      setState(() {
        _offset = (_offset + event.scrollDelta.dy).clamp(0.0, _maxOffset);
      });
      return;
    }
    final base = _zoomId == id ? _scale : 1.0;
    final scale = (base * math.exp(-event.scrollDelta.dy * 0.0016)).clamp(1.0, 5.0);
    if (scale <= 1.02) {
      _dismissZoom();
      return;
    }
    _keepZoom();
    _armOriginal(id);
    setState(() {
      _zoomId = id;
      _scale = scale;
      _zoomOpacity = 1;
    });
    _armZoomEnd();
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
  final String locateLabel;
  final GlobalKey locateKey;

  const _Polaroid({
    required this.asset,
    required this.flipped,
    required this.caption,
    required this.locateLabel,
    required this.locateKey,
  });

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return _Flip(
      flipped: flipped,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 520),
      front: _Face(asset: asset, caption: caption),
      back: _Back(asset: asset, locateLabel: locateLabel, locateKey: locateKey),
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
  final String locateLabel;
  final GlobalKey locateKey;

  const _Back({required this.asset, required this.locateLabel, required this.locateKey});

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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      Padding(
                        padding: EdgeInsets.only(bottom: i == 0 ? 10 : 4),
                        child: Text(
                          lines[i],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: i == lines.length - 1 ? DeskColors.muted : DeskColors.ink,
                            fontSize: i == 0 ? 15 : 13,
                            height: 1.3,
                            fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              key: locateKey,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: DeskColors.ink.withOpacity(0.35)),
              ),
              child: Text(
                locateLabel,
                style: const TextStyle(color: DeskColors.ink, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OriginalPhoto extends StatelessWidget {
  final MediaAsset asset;
  final String? path;

  const _OriginalPhoto({required this.asset, required this.path});

  @override
  Widget build(BuildContext context) {
    final file = path == null || path!.isEmpty ? null : File(path!);
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 16))],
      ),
      child: file == null
          ? _Still(asset: asset, fit: BoxFit.contain)
          : Image.file(
              file,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => _Still(asset: asset, fit: BoxFit.contain),
            ),
    );
  }
}

class _Still extends StatelessWidget {
  final MediaAsset asset;
  final BoxFit fit;

  const _Still({required this.asset, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final bytes = asset.thumbnailBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: fit, gaplessPlayback: true);
    }
    final path = asset.thumbnailPath;
    if (path != null && path.isNotEmpty) {
      return Image.file(File(path), fit: fit, gaplessPlayback: true);
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
