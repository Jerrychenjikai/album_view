import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_asset.dart';
import '../models/media_batch.dart';
import '../theme/app_theme.dart';
import '../timeline/day_number.dart';
import '../timeline/timeline_metrics.dart';

class BatchStack extends StatelessWidget {
  final MediaBatch batch;
  final VoidCallback onTap;

  const BatchStack({
    super.key,
    required this.batch,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = batch.items;
    if (items.isEmpty) return const SizedBox.shrink();
    final top = batch.resolvedTopIndex;
    final layers = <int>[];
    final under = items.length < 4 ? items.length - 1 : 3;
    for (var depth = under; depth >= 1; depth--) {
      layers.add(positiveMod(top - depth, items.length));
    }
    layers.add(top);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: TimelineMetrics.cardWidth + TimelineMetrics.fan * 2,
        height: TimelineMetrics.cardHeight + TimelineMetrics.fan,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < layers.length; i++)
              _Print(
                asset: items[layers[i]],
                depthFromTop: layers.length - 1 - i,
                baseRotation: batch.rotation,
                caption: _caption(batch),
                city: batch.dominantCity,
                showCaption: layers[i] == top,
              ),
          ],
        ),
      ),
    );
  }

  String _caption(MediaBatch batch) {
    final count = batch.items.length;
    final label = batch.label.isEmpty ? '${batch.day.month}月${batch.day.day}日' : batch.label;
    if (count <= 1) return label;
    return '$label · $count';
  }
}

class _Print extends StatelessWidget {
  final MediaAsset asset;
  final int depthFromTop;
  final double baseRotation;
  final String caption;
  final String? city;
  final bool showCaption;

  const _Print({
    required this.asset,
    required this.depthFromTop,
    required this.baseRotation,
    required this.caption,
    required this.city,
    required this.showCaption,
  });

  @override
  Widget build(BuildContext context) {
    final dx = depthFromTop == 0 ? 0.0 : -depthFromTop * 7.0;
    final dy = depthFromTop * 5.0;
    final angle = baseRotation + depthFromTop * 0.035 * (depthFromTop.isOdd ? -1 : 1);
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: TimelineMetrics.cardWidth,
          height: TimelineMetrics.cardHeight,
          decoration: BoxDecoration(
            color: DeskColors.paper,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFFE4DCCB)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withOpacity(0.38),
                blurRadius: 14,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(7, 7, 7, 8),
          child: Column(
            children: [
              Expanded(child: ClipRect(child: _Preview(asset: asset))),
              const SizedBox(height: 6),
              SizedBox(
                height: 28,
                width: double.infinity,
                child: showCaption
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: DeskColors.ink,
                              fontSize: 11,
                              height: 1.15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                          Text(
                            city ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF6E6558),
                              fontSize: 10,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  final MediaAsset asset;
  const _Preview({required this.asset});

  @override
  Widget build(BuildContext context) {
    final bytes = asset.thumbnailBytes;
    Widget image;
    if (bytes != null && bytes.isNotEmpty) {
      image = Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    } else if (asset.thumbnailPath != null && asset.thumbnailPath!.isNotEmpty) {
      image = Image.file(
        File(asset.thumbnailPath!),
        fit: BoxFit.cover,
        cacheWidth: 360,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    } else {
      image = _Fallback(asset: asset);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        if (asset.kind == MediaKind.video)
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              margin: const EdgeInsets.all(6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: const Color(0xCC1C1814),
              child: Text(
                asset.durationLabel.isEmpty ? '视频' : asset.durationLabel,
                style: const TextStyle(color: DeskColors.paper, fontSize: 10, letterSpacing: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}

class _Fallback extends StatelessWidget {
  final MediaAsset asset;
  const _Fallback({required this.asset});

  @override
  Widget build(BuildContext context) {
    final hue = (unitHash(asset.id) * 40 + 18).round();
    final wash = HSLColor.fromAHSL(1, hue.toDouble(), 0.28, 0.42).toColor();
    final deep = HSLColor.fromAHSL(1, (hue + 12).toDouble(), 0.22, 0.24).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [wash, deep],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            asset.fileName,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: DeskColors.paper, fontSize: 11, height: 1.3),
          ),
        ),
      ),
    );
  }
}
