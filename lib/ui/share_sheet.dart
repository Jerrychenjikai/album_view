import 'dart:io';
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

  const ShareSheet({
    super.key,
    required this.items,
    required this.resolveOriginal,
    required this.onNeedThumbs,
    required this.onClose,
  });

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final List<String> _picked = [];
  final GlobalKey _exportKey = GlobalKey();
  Uint8List? _card;
  int _style = 0;
  int _ticket = 0;
  String _note = '';
  double _drag = 0;
  bool _exporting = false;
  final Set<String> _thumbAsked = {};

  List<MediaAsset> get _images => widget.items.where((item) => item.kind == MediaKind.image).toList();

  @override
  void initState() {
    super.initState();
    _rebuild();
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
      setState(() => _card = jpg);
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
    setState(() => _style = next);
    _rebuild();
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

  @override
  Widget build(BuildContext context) {
    final style = shareStyles[_style];
    final images = _images;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: const ColoredBox(color: Color(0x8C1A1612)),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: widget.onClose,
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
                      child: Center(
                        child: _card == null
                            ? const Text('正在铺桌子…', style: TextStyle(color: DeskColors.muted))
                            : Image.memory(_card!, fit: BoxFit.contain, gaplessPlayback: true),
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
                SizedBox(
                  height: 96,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    cacheExtent: 160,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: images.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final asset = images[index];
                      final order = _picked.indexOf(asset.id);
                      final on = order >= 0;
                      return GestureDetector(
                        onTap: () => _toggle(asset),
                        child: Container(
                          width: 58,
                          padding: const EdgeInsets.fromLTRB(3, 3, 3, 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFB59262),
                            border: Border.all(color: on ? DeskColors.amber : Colors.transparent, width: 2),
                          ),
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
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
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
