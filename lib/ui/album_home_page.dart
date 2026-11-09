import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../loaders/image_loader.dart';
import '../models/media_asset.dart';
import '../models/media_batch.dart';
import '../share/share_card.dart';
import '../state/album_controller.dart';
import '../theme/app_theme.dart';
import '../timeline/time_resolution.dart';
import '../timeline/timeline_metrics.dart';
import 'batch_preview.dart';
import 'share_sheet.dart';
import 'timeline_board.dart';

class AlbumHomePage extends StatefulWidget {
  final AlbumController controller;

  const AlbumHomePage({super.key, required this.controller});

  @override
  State<AlbumHomePage> createState() => _AlbumHomePageState();
}

class _AlbumHomePageState extends State<AlbumHomePage> {
  AlbumController get controller => widget.controller;
  double _track = 640;
  List<MediaBatch>? _cachedBatches;
  (int, QuickRange, MediaKind?, double, double)? _layoutKey;

  bool _picking = false;
  bool _shareArmed = false;
  MediaBatch? _shareBatch;
  Offset? _shareOrigin;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChange);
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bootMac());
    } else {
      controller.reload();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// While a zoom gesture is in progress the groupings stay put, so don't
  /// rebuild every stack on each wheel tick. Progress ticks that don't add
  /// photos reuse the same arrangement too.
  List<MediaBatch> _layout(double track) {
    if (controller.zooming && _cachedBatches != null) return _cachedBatches!;
    final key = (
      identityHashCode(controller.master),
      controller.quickRange,
      controller.kind,
      controller.viewport.pixelsPerDay,
      track,
    );
    final cached = _cachedBatches;
    if (cached != null && _layoutKey == key) return cached;
    final next = controller.layout(track);
    _layoutKey = key;
    _cachedBatches = next;
    return next;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.minus): () => _zoom(1 / 1.18),
        const SingleActivator(LogicalKeyboardKey.equal): () => _zoom(1.18),
        const SingleActivator(LogicalKeyboardKey.numpadAdd): () => _zoom(1.18),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () => _zoom(1 / 1.18),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            controller.panBy(-120, viewWidth: MediaQuery.sizeOf(context).width),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            controller.panBy(120, viewWidth: MediaQuery.sizeOf(context).width),
        const SingleActivator(LogicalKeyboardKey.escape): controller.closePreview,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: SafeArea(
            child: Stack(
                  children: [
                    Column(
                      children: [
                        _Toolbar(
                          controller: controller,
                          track: _track,
                          onFolder: _editFolder,
                          shareArmed: _shareArmed,
                          onShare: _onPhone ? _toggleShare : null,
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, boardConstraints) {
                              final track = (boardConstraints.maxHeight - TimelineMetrics.rulerHeight - 16)
                                  .clamp(1.0, 10000.0)
                                  .toDouble();
                              if ((track - _track).abs() > 1) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (mounted && (_track - track).abs() > 1) setState(() => _track = track);
                                });
                              }
                              final batches = _layout(track);
                              return TimelineBoard(
                                controller: controller,
                                trackHeight: track,
                                viewWidth: boardConstraints.maxWidth,
                                batches: batches,
                                shareArmed: _shareArmed,
                                onShareBatch: _tryShare,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    if (controller.previewItems.isNotEmpty)
                      Positioned.fill(
                        child: BatchPreview(
                          items: controller.previewItems,
                          rows: TimelineMetrics.laneCount(_track),
                          resolution: controller.resolutionFor(_track),
                          originGlobal: controller.previewOrigin,
                          onClose: controller.closePreview,
                          locateLabel: _onPhone ? '在相册中显示' : '在文件夹中显示',
                          resolveOriginal: controller.loader.materializeOriginal,
                          onReveal: _revealAsset,
                          onFocusPage: controller.prioritizeThumbs,
                        ),
                      ),
                    if (_shareBatch != null)
                      Positioned.fill(
                        child: ShareSheet(
                          items: _shareItems(),
                          originGlobal: _shareOrigin,
                          onNeedThumbs: controller.prioritizeThumbs,
                          resolveOriginal: controller.loader.materializeOriginal,
                          onClose: () => setState(() {
                            _shareBatch = null;
                            _shareOrigin = null;
                          }),
                        ),
                      ),
                  ],
                ),
          ),
        ),
      ),
    );
  }

  bool get _onPhone =>
      defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;

  Future<void> _revealAsset(MediaAsset asset) async {
    try {
      await controller.loader.reveal(asset);
    } catch (error) {
      if (!mounted) return;
      final text = error is LibraryException ? error.message : '无法打开这张照片';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _zoom(double factor) {
    final width = MediaQuery.sizeOf(context).width;
    controller.zoomAt(focalScreenX: width / 2, factor: factor, viewWidth: width);
  }

  void _toggleShare() {
    setState(() {
      _shareArmed = !_shareArmed;
      if (!_shareArmed) {
        _shareBatch = null;
        _shareOrigin = null;
      }
    });
  }

  void _tryShare(MediaBatch batch, Offset? origin) {
    if (batch.items.length > sharePhotoLimit) {
      _toast('这一摞超过 100 张。请放大时间轴之后再点选。');
      return;
    }
    if (!batch.items.any((item) => item.kind == MediaKind.image)) {
      _toast('这一摞里没有可以分享的照片。');
      return;
    }
    setState(() {
      _shareBatch = batch;
      _shareOrigin = origin;
    });
    final photos = [for (final item in batch.items) if (item.kind == MediaKind.image) item];
    controller.prioritizeThumbs(photos.take(8).toList());
  }

  List<MediaAsset> _shareItems() {
    final batch = _shareBatch;
    if (batch == null) return const [];
    final byId = {for (final asset in controller.master) asset.id: asset};
    return [for (final item in batch.items) byId[item.id] ?? item];
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
    );
  }

  Future<void> _bootMac() async {
    if (!mounted) return;
    final stored = await controller.loader.storedImagePath();
    if (!mounted) return;
    if (stored == null || stored.isEmpty) {
      await _pickMacFolder();
      return;
    }
    await controller.reload();
  }

  Future<void> _pickMacFolder() async {
    if (_picking) return;
    _picking = true;
    try {
      final stored = await controller.loader.storedImagePath();
      final initial = stored != null && stored.startsWith('/') ? stored : null;
      final picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择照片文件夹',
        lockParentWindow: true,
        initialDirectory: initial,
      );
      if (!mounted) return;
      if (picked == null || picked.trim().isEmpty) {
        if (controller.master.isEmpty && !controller.loading) {
          await controller.reload();
        }
        return;
      }
      await controller.setFolder(picked.trim());
    } catch (error) {
      if (!mounted) return;
      final text = error is LibraryException ? error.message : '没法打开文件夹窗口';
      controller.error = text;
      setState(() {});
    } finally {
      _picking = false;
    }
  }

  Future<void> _editFolder() async {
    final mobile = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
    if (mobile || !controller.loader.canConfigureFolder) return;
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _pickMacFolder();
      return;
    }
    final stored = await controller.loader.storedImagePath();
    if (!mounted) return;
    final field = TextEditingController(text: stored ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: DeskColors.raised,
          title: const Text('照片文件夹'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '填写照片所在的文件夹。留空则改回程序旁边的文件夹。会连同子文件夹里的照片和视频一起读。',
                style: TextStyle(color: DeskColors.muted, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: field,
                autofocus: true,
                style: const TextStyle(color: DeskColors.paper),
                decoration: const InputDecoration(
                  hintText: r'D:\Photos',
                  hintStyle: TextStyle(color: DeskColors.muted),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: DeskColors.line)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: DeskColors.amber)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(context, field.text),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    field.dispose();
    if (result == null) return;
    await controller.setFolder(result);
  }
}

class _Toolbar extends StatelessWidget {
  final AlbumController controller;
  final double track;
  final VoidCallback onFolder;
  final bool shareArmed;
  final VoidCallback? onShare;

  const _Toolbar({
    required this.controller,
    required this.track,
    required this.onFolder,
    required this.shareArmed,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final resolution = controller.resolutionFor(track);
    final mobile = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android;
    final allowFolder = controller.loader.canConfigureFolder && !mobile;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DeskColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('光桌', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 1.2)),
              const Spacer(),
              Text('按${resolution.label}', style: const TextStyle(color: DeskColors.muted, fontSize: 13)),
              const SizedBox(width: 4),
              _IconButton(
                tooltip: '回到今天',
                label: '今天',
                onPressed: () => controller.revealToday(MediaQuery.sizeOf(context).width),
              ),
              if (allowFolder)
                _IconButton(
                  tooltip: defaultTargetPlatform == TargetPlatform.macOS ? '选择文件夹' : '照片文件夹',
                  label: '来源',
                  onPressed: onFolder,
                ),
              if (!controller.loading && (controller.error != null || controller.master.isEmpty))
                _IconButton(tooltip: '重新读取', label: '读取', onPressed: () => controller.reload()),
              if (onShare != null && !shareArmed)
                _IconButton(tooltip: '分享', label: '分享', onPressed: onShare!),
            ],
          ),
          if (onShare != null && shareArmed)
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('点击一个batch来分享', style: TextStyle(color: DeskColors.amber, fontSize: 13)),
                  TextButton(
                    onPressed: onShare,
                    style: TextButton.styleFrom(
                      foregroundColor: DeskColors.paper,
                      minimumSize: const Size(44, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
          if (controller.loading)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: controller.scanFraction,
                      minHeight: 4,
                      color: DeskColors.amber,
                      backgroundColor: DeskColors.line,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    controller.scanLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: DeskColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          if (!controller.loading && controller.sourceLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Text(
                controller.sourceLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: DeskColors.muted, fontSize: 12),
              ),
            ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(
                controller.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFE07A62), fontSize: 12, height: 1.35),
              ),
            ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final range in QuickRange.values)
                  _Chip(
                    label: switch (range) {
                      QuickRange.all => '全部',
                      QuickRange.days7 => '近 7 天',
                      QuickRange.days30 => '近 30 天',
                      QuickRange.thisYear => '今年',
                    },
                    selected: controller.quickRange == range,
                    onTap: () => controller.setQuickRange(range),
                  ),
                _Chip(
                  label: '照片',
                  selected: controller.kind == MediaKind.image,
                  onTap: () => controller.setKind(controller.kind == MediaKind.image ? null : MediaKind.image),
                ),
                _Chip(
                  label: '视频',
                  selected: controller.kind == MediaKind.video,
                  onTap: () => controller.setKind(controller.kind == MediaKind.video ? null : MediaKind.video),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? DeskColors.amber : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: selected ? DeskColors.amber : DeskColors.line),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? DeskColors.ink : DeskColors.paper,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  const _IconButton({required this.label, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: DeskColors.paper,
          minimumSize: const Size(44, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        child: Text(label),
      ),
    );
  }
}
