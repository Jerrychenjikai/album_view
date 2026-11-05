import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_asset.dart';
import '../state/album_controller.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline_metrics.dart';
import 'batch_preview.dart';
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

  @override
  void initState() {
    super.initState();
    controller.addListener(_onChange);
    controller.reload();
  }

  @override
  void dispose() {
    controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.minus): () => _zoom(1 / 1.18),
        const SingleActivator(LogicalKeyboardKey.equal): () => _zoom(1.18),
        const SingleActivator(LogicalKeyboardKey.numpadAdd): () => _zoom(1.18),
        const SingleActivator(LogicalKeyboardKey.numpadSubtract): () => _zoom(1 / 1.18),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => controller.panBy(-120),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => controller.panBy(120),
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
                          onZoom: _zoom,
                          onFolder: _editFolder,
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
                              final batches = controller.layout(track);
                              return TimelineBoard(
                                controller: controller,
                                trackHeight: track,
                                viewWidth: boardConstraints.maxWidth,
                                batches: batches,
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
                          onClose: controller.closePreview,
                        ),
                      ),
                  ],
                ),
          ),
        ),
      ),
    );
  }

  void _zoom(double factor) {
    final width = MediaQuery.sizeOf(context).width;
    controller.zoomAt(focalScreenX: width / 2, factor: factor, viewWidth: width);
  }

  Future<void> _editFolder() async {
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
                '写入 shared preferences 的 image_path。留空则改回 app 所在文件夹。会读取该目录以及所有子文件夹里的照片和视频。',
                style: TextStyle(color: DeskColors.muted, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: field,
                autofocus: true,
                style: const TextStyle(color: DeskColors.paper),
                decoration: const InputDecoration(
                  hintText: '/Users/me/Pictures',
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
  final void Function(double factor) onZoom;
  final VoidCallback onFolder;

  const _Toolbar({
    required this.controller,
    required this.track,
    required this.onZoom,
    required this.onFolder,
  });

  @override
  Widget build(BuildContext context) {
    final resolution = controller.resolutionFor(track);
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
              _IconButton(tooltip: '缩小', label: '−', onPressed: () => onZoom(1 / 1.18)),
              _IconButton(tooltip: '放大', label: '+', onPressed: () => onZoom(1.18)),
              _IconButton(
                tooltip: '回到今天',
                label: '今天',
                onPressed: () => controller.revealToday(MediaQuery.sizeOf(context).width),
              ),
              if (controller.loader.canConfigureFolder)
                _IconButton(tooltip: '照片文件夹', label: '来源', onPressed: onFolder),
            ],
          ),
          if (controller.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(
                controller.error!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFE07A62), fontSize: 12),
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
