import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/media_asset.dart';
import '../share/share_card.dart';
import '../theme/app_theme.dart';

class ShareSheet extends StatefulWidget {
  final List<MediaAsset> items;
  final Future<String?> Function(MediaAsset asset) resolveOriginal;
  final void Function(List<MediaAsset> assets) onNeedThumbs;
  final VoidCallback onClose;
  final Offset? originGlobal;

  const ShareSheet({
    super.key,
    required this.items,
    required this.resolveOriginal,
    required this.onNeedThumbs,
    required this.onClose,
    this.originGlobal,
  });

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> with TickerProviderStateMixin {
  final List<String> _picked = [];
  final GlobalKey _exportKey = GlobalKey();
  Uint8List? _card;
  Uint8List? _outgoing;
  int _style = 0;
  int _ticket = 0;
  int _slideDir = 0;
  int _pendingSlide = 0;
  String _note = '';
  double _drag = 0;
  double _strip = 0;
  bool _exporting = false;
  bool _closing = false;
  final Set<String> _thumbAsked = {};
  late final AnimationController _spread;
  late final AnimationController _slide;

  List<MediaAsset> get _images => widget.items.where((item) => item.kind == MediaKind.image).toList();

  @override
  void initState() {
    super.initState();
    _spread = AnimationController(vsync: this, duration: const Duration(milliseconds: 560))
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 360))
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _outgoing = null);
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _spread.value = 1;
      } else {
        _spread.animateTo(1, curve: Curves.easeOutCubic);
      }
    });
    _rebuild();
  }

  @override
  void dispose() {
    _spread.dispose();
    _slide.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ShareSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_picked.isEmpty) return;
    var changed = false;
    for (final id in _picked) {
      final before = _lookup(oldWidget.items, id);
      final after = _lookup(widget.items, id);
      if (before?.thumbnailPath != after?.thumbnailPath || before?.hasThumbnail != after?.hasThumbnail) {
        changed = true;
        break;
      }
    }
    if (changed) _rebuild();
  }

  MediaAsset? _lookup(List<MediaAsset> items, String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _askThumb(MediaAsset asset) {
    if (asset.hasThumbnail || _thumbAsked.contains(asset.id)) return;
    _thumbAsked.add(asset.id);
    widget.onNeedThumbs([asset]);
  }

  Future<Uint8List?> _bytes(MediaAsset asset) async {
    try {
      final path = await widget.resolveOriginal(asset);
      if (path != null && path.isNotEmpty && await File(path).exists()) {
        return File(path).readAsBytes();
      }
    } catch (_) {}
    final thumb = asset.thumbnailPath;
    if (thumb != null && thumb.isNotEmpty && await File(thumb).exists()) {
      return File(thumb).readAsBytes();
    }
    final memory = asset.thumbnailBytes;
    if (memory != null && memory.isNotEmpty) return memory;
    _askThumb(asset);
    return null;
  }

  Future<void> _rebuild() async {
    final ticket = ++_ticket;
    final photos = <Uint8List>[];
    for (final id in _picked) {
      MediaAsset? asset;
      for (final item in _images) {
        if (item.id == id) asset = item;
      }
      if (asset == null) continue;
      final bytes = await _bytes(asset);
      if (bytes != null && bytes.isNotEmpty) photos.add(bytes);
    }
    try {
      final jpg = await composeShareCard(photos, styleId: shareStyles[_style].id);
      if (!mounted || ticket != _ticket) return;
      final slide = _pendingSlide;
      _pendingSlide = 0;
      final reduce = MediaQuery.disableAnimationsOf(context);
      setState(() {
        if (slide != 0 && _card != null && !reduce) {
          _outgoing = _card;
          _slideDir = slide;
          _slide.forward(from: 0);
        } else {
          _outgoing = null;
        }
        _card = jpg;
      });
    } catch (_) {
      if (!mounted || ticket != _ticket) return;
      setState(() => _note = '这张分享图没有铺好');
    }
  }

  void _toggle(MediaAsset asset) {
    setState(() {
      if (_picked.contains(asset.id)) {
        _picked.remove(asset.id);
        _note = '';
      } else if (_picked.length >= 3) {
        _note = '最多三张';
        return;
      } else {
        _picked.add(asset.id);
        _note = '';
      }
    });
    _rebuild();
  }

  void _shift(int dir) {
    final next = (_style + dir).clamp(0, shareStyles.length - 1);
    if (next == _style) return;
    _pendingSlide = dir;
    setState(() => _style = next);
    _rebuild();
  }

  Future<void> _requestClose() async {
    if (_closing) return;
    _closing = true;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (!reduce && _spread.value > 0.02) {
      await _spread.animateBack(0, duration: const Duration(milliseconds: 420), curve: Curves.easeIn);
    }
    if (mounted) widget.onClose();
  }

  Future<void> _export() async {
    final bytes = _card;
    if (bytes == null || bytes.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'lighttable-share.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final node = _exportKey.currentContext?.findRenderObject();
      final box = node is RenderBox && node.hasSize ? node : null;
      final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/jpeg', name: '光桌.jpg')],
        subject: '光桌',
        sharePositionOrigin: origin,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _note = '系统没有打开分享');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Offset _localOrigin(Size size) {
    final global = widget.originGlobal;
    final box = context.findRenderObject() as RenderBox?;
    if (global == null || box == null || !box.hasSize) {
      return Offset(size.width / 2, size.height / 2);
    }
    return box.globalToLocal(global);
  }

  @override
  Widget build(BuildContext context) {
    final style = shareStyles[_style];
    final images = _images;
    final t = _spread.value.clamp(0.0, 1.0);
    final chrome = ((t - 0.08) / 0.45).clamp(0.0, 1.0);
    final slideT = Curves.easeOutCubic.transform(_slide.value.clamp(0.0, 1.0));
    return Material(
      type: MaterialType.transparency,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final origin = _localOrigin(size);
          final padding = MediaQuery.paddingOf(context);
          const thumbW = 58.0;
          const thumbH = 76.0;
          const stride = 66.0;
          final maxStrip = (24 + images.length * stride - 8 - size.width).clamp(0.0, 100000.0);
          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Opacity(
                    opacity: t,
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: const ColoredBox(color: Color(0x8C1A1612)),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: chrome < 0.4,
                  child: Opacity(
                    opacity: chrome,
                    child: SafeArea(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              TextButton(
                                onPressed: _requestClose,
                                child: const Text('返回', style: TextStyle(color: DeskColors.paper)),
                              ),
                              Expanded(
                                child: Text(
                                  '${style.label} · ${_style + 1}/${shareStyles.length}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: DeskColors.muted, fontSize: 13),
                                ),
                              ),
                              TextButton(
                                key: _exportKey,
                                onPressed: _export,
                                child: Text(_exporting ? '…' : '导出', style: const TextStyle(color: DeskColors.amber)),
                              ),
                            ],
                          ),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onHorizontalDragUpdate: (event) => _drag += event.delta.dx,
                              onHorizontalDragEnd: (_) {
                                if (_drag <= -48) _shift(1);
                                if (_drag >= 48) _shift(-1);
                                _drag = 0;
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: ClipRect(
                                  child: Center(child: _preview(slideT)),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                            child: Text(
                              _note.isEmpty ? '点下面的照片，最多三张 · 左右滑动换风格' : _note,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _note.isEmpty ? DeskColors.muted : const Color(0xFFE07A62), fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 96),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              for (var index = 0; index < images.length; index++)
                _flyingThumb(
                  asset: images[index],
                  index: index,
                  count: images.length,
                  origin: origin,
                  t: t,
                  size: size,
                  padding: padding,
                  thumbW: thumbW,
                  thumbH: thumbH,
                  stride: stride,
                  maxStrip: maxStrip,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _preview(double slideT) {
    final current = _card;
    if (current == null) {
      return const Text('正在排版…', style: TextStyle(color: DeskColors.muted));
    }
    final outgoing = _outgoing;
    if (outgoing == null || _slideDir == 0) {
      return Image.memory(current, fit: BoxFit.contain, gaplessPlayback: true);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.translate(
              offset: Offset(-_slideDir * slideT * width, 0),
              child: Image.memory(outgoing, fit: BoxFit.contain, gaplessPlayback: true),
            ),
            Transform.translate(
              offset: Offset(_slideDir * (1 - slideT) * width, 0),
              child: Image.memory(current, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ],
        );
      },
    );
  }

  Widget _flyingThumb({
    required MediaAsset asset,
    required int index,
    required int count,
    required Offset origin,
    required double t,
    required Size size,
    required EdgeInsets padding,
    required double thumbW,
    required double thumbH,
    required double stride,
    required double maxStrip,
  }) {
    final depth = math.min(3, math.max(0, count - 1 - index));
    final fan = Offset(depth == 0 ? 0 : -depth * 7.0, depth * 5.0);
    final target = Offset(
      padding.left + 12 + index * stride + thumbW / 2 - _strip,
      size.height - padding.bottom - 12 - thumbH / 2,
    );
    final center = Offset.lerp(origin + fan, target, t)!;
    final w = 142 + (thumbW - 142) * t;
    final h = 172 + (thumbH - 172) * t;
    final fade = ((t - 0.02) / 0.35).clamp(0.0, 1.0);
    final order = _picked.indexOf(asset.id);
    final on = order >= 0;
    return Positioned(
      left: center.dx - w / 2,
      top: center.dy - h / 2,
      width: w,
      height: h,
      child: IgnorePointer(
        ignoring: t < 0.98,
        child: Opacity(
          opacity: fade,
          child: GestureDetector(
            onTap: () => _toggle(asset),
            onHorizontalDragUpdate: (event) {
              setState(() => _strip = (_strip - event.delta.dx).clamp(0.0, maxStrip));
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFB59262),
                border: Border.all(color: on ? DeskColors.amber : Colors.transparent, width: 2),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(3, 3, 3, 4 + 4 * t),
                child: Stack(
                  children: [
                    Positioned.fill(child: _LazyThumb(asset: asset, onNeed: _askThumb)),
                    if (on)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          color: DeskColors.amber,
                          child: Text(
                            '${order + 1}',
                            style: const TextStyle(color: DeskColors.ink, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LazyThumb extends StatefulWidget {
  final MediaAsset asset;
  final void Function(MediaAsset asset) onNeed;

  const _LazyThumb({required this.asset, required this.onNeed});

  @override
  State<_LazyThumb> createState() => _LazyThumbState();
}

class _LazyThumbState extends State<_LazyThumb> {
  @override
  void initState() {
    super.initState();
    _ask();
  }

  @override
  void didUpdateWidget(_LazyThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) _ask();
  }

  void _ask() {
    if (widget.asset.hasThumbnail) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.asset.hasThumbnail) return;
      widget.onNeed(widget.asset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final bytes = asset.thumbnailBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
    }
    final path = asset.thumbnailPath;
    if (path != null && path.isNotEmpty) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: 160,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) {
          widget.onNeed(asset);
          return const _ThumbWait();
        },
      );
    }
    return const _ThumbWait();
  }
}

class _ThumbWait extends StatelessWidget {
  const _ThumbWait();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A7156), Color(0xFF4E4034)],
        ),
      ),
    );
  }
}
