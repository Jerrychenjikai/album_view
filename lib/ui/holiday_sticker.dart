import 'package:flutter/material.dart';

import '../models/holiday.dart';
import '../timeline/day_number.dart';

/// Renders a small festive holiday sticker at a random edge position.
class HolidayStickerWidget extends StatelessWidget {
  final Holiday holiday;
  final String seed;
  final double cardWidth;
  final double cardHeight;
  final double stickerSize;
  final bool isPolaroid;

  const HolidayStickerWidget({
    super.key,
    required this.holiday,
    required this.seed,
    required this.cardWidth,
    required this.cardHeight,
    required this.stickerSize,
    this.isPolaroid = false,
  });

  /// Factory for timeline batch stack sticker.
  static Widget forBatch({
    required Holiday holiday,
    required String seed,
    required double cardWidth,
    required double cardHeight,
    double stickerSize = 32.0,
  }) {
    return HolidayStickerWidget(
      holiday: holiday,
      seed: seed,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      stickerSize: stickerSize,
      isPolaroid: false,
    );
  }

  /// Factory for batch preview Polaroid frame sticker.
  static Widget forPolaroid({
    required Holiday holiday,
    required String seed,
    required double cardWidth,
    required double cardHeight,
  }) {
    final stickerSize = (cardWidth * 0.18).clamp(24.0, 36.0);
    return HolidayStickerWidget(
      holiday: holiday,
      seed: seed,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      stickerSize: stickerSize,
      isPolaroid: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final variant = holiday.variantForSeed(seed);
    final assetPath = holiday.assetPath(variant);

    // Calculate random position on the batch edge or polaroid frame
    final side = (unitHash('$seed-side') * 4).floor().clamp(0, 3);
    final t = unitHash('$seed-pos');
    final jitter = unitHash('$seed-jitter') - 0.5;
    final tilt = (unitHash('$seed-tilt') - 0.5) * 0.45;

    double left = 0;
    double top = 0;

    if (!isPolaroid) {
      // Timeline batch edge placement
      switch (side) {
        case 0: // Top edge
          left = 6.0 + t * (cardWidth - stickerSize - 12.0);
          top = -stickerSize * 0.35 + jitter * 6.0;
          break;
        case 1: // Right edge
          left = cardWidth - stickerSize * 0.65 + jitter * 6.0;
          top = 8.0 + t * (cardHeight - stickerSize - 16.0);
          break;
        case 2: // Bottom edge
          left = 6.0 + t * (cardWidth - stickerSize - 12.0);
          top = cardHeight - stickerSize * 0.65 + jitter * 6.0;
          break;
        case 3: // Left edge
          left = -stickerSize * 0.35 + jitter * 6.0;
          top = 8.0 + t * (cardHeight - stickerSize - 16.0);
          break;
      }
    } else {
      // Polaroid frame placement (chin, top margin, side borders)
      switch (side) {
        case 0: // Top border
          left = 4.0 + t * (cardWidth - stickerSize - 8.0);
          top = -stickerSize * 0.15 + jitter * 4.0;
          break;
        case 1: // Right border
          left = cardWidth - stickerSize * 0.85 + jitter * 4.0;
          top = 6.0 + t * (cardHeight - stickerSize - 12.0);
          break;
        case 2: // Bottom chin (polaroid wide caption space)
          left = 6.0 + t * (cardWidth - stickerSize - 12.0);
          top = cardHeight - stickerSize * 0.95 + jitter * 4.0;
          break;
        case 3: // Left border
          left = -stickerSize * 0.15 + jitter * 4.0;
          top = 6.0 + t * (cardHeight - stickerSize - 12.0);
          break;
      }
    }

    return Positioned(
      left: left,
      top: top,
      width: stickerSize,
      height: stickerSize,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: tilt,
          child: Image.asset(
            assetPath,
            width: stickerSize,
            height: stickerSize,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
