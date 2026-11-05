import '../models/media_batch.dart';

enum FlightKind { mergeOut, fadeOut, fadeIn, splitIn }

class FlightCard {
  final String key;
  final MediaBatch batch;
  final double fromDays;
  final double toDays;
  final double fromY;
  final double toY;
  final FlightKind kind;

  const FlightCard({
    required this.key,
    required this.batch,
    required this.fromDays,
    required this.toDays,
    required this.fromY,
    required this.toY,
    required this.kind,
  });
}

class FlightPose {
  final double days;
  final double y;
  final double opacity;
  final double scale;

  const FlightPose({required this.days, required this.y, required this.opacity, required this.scale});
}

class ResolutionFlight {
  final bool merge;
  final int outMs;
  final int inMs;
  final List<FlightCard> outCards;
  final List<FlightCard> inCards;

  const ResolutionFlight({
    required this.merge,
    required this.outMs,
    required this.inMs,
    required this.outCards,
    required this.inCards,
  });
}

double _ease(double t) {
  final x = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  return x < 0.5 ? 4 * x * x * x : 1 - _cube(-2 * x + 2) / 2;
}

double _cube(double v) => v * v * v;

double _lerp(double a, double b, double t) => a + (b - a) * t;

FlightPose poseOf(FlightCard card, double t) {
  final clamped = t < 0 ? 0.0 : (t > 1 ? 1.0 : t);
  final eased = _ease(clamped);
  switch (card.kind) {
    case FlightKind.mergeOut:
      return FlightPose(
        days: _lerp(card.fromDays, card.toDays, eased),
        y: _lerp(card.fromY, card.toY, eased),
        opacity: _coverFade(clamped, 0.78, 1),
        scale: 1,
      );
    case FlightKind.fadeOut:
      return FlightPose(
        days: card.fromDays,
        y: card.fromY,
        opacity: _coverFade(clamped, 0.02, 0.22),
        scale: 1,
      );
    case FlightKind.fadeIn:
    case FlightKind.splitIn:
      return FlightPose(
        days: _lerp(card.fromDays, card.toDays, eased),
        y: _lerp(card.fromY, card.toY, eased),
        opacity: 1,
        scale: 1,
      );
  }
}

double _coverFade(double t, double start, double end) {
  if (t <= start) return 1;
  if (t >= end) return 0;
  return 1 - (t - start) / (end - start);
}

double _daysOf(MediaBatch batch, double ppd) => batch.position.dx / (ppd <= 0 ? 1 : ppd);

MediaBatch? _majority(MediaBatch batch, List<MediaBatch> targets) {
  final ids = {for (final item in batch.items) item.id};
  MediaBatch? best;
  var count = 0;
  for (final target in targets) {
    var n = 0;
    for (final item in target.items) {
      if (ids.contains(item.id)) n++;
    }
    if (n > count) {
      best = target;
      count = n;
    }
  }
  return best;
}

MediaBatch? _parent(MediaBatch batch, List<MediaBatch> parents) {
  if (batch.items.isEmpty) return null;
  final id = batch.items.first.id;
  for (final parent in parents) {
    for (final item in parent.items) {
      if (item.id == id) return parent;
    }
  }
  return null;
}

/// Old and new batches share one pass. New ones are drawn underneath first.
ResolutionFlight planResolutionFlight({
  required List<MediaBatch> from,
  required double fromPpd,
  required List<MediaBatch> to,
  required double toPpd,
  required bool coarser,
}) {
  if (coarser) {
    return ResolutionFlight(
      merge: true,
      outMs: 560,
      inMs: 0,
      outCards: [for (final batch in from) _mergeOut(batch, fromPpd, to, toPpd)],
      inCards: [for (final batch in to) _settleIn(batch, toPpd, from, fromPpd)],
    );
  }
  return ResolutionFlight(
    merge: false,
    outMs: 560,
    inMs: 0,
    outCards: [for (final batch in from) _fadeOut(batch, fromPpd)],
    inCards: [for (final batch in to) _splitIn(batch, toPpd, from, fromPpd)],
  );
}

FlightCard _mergeOut(MediaBatch batch, double fromPpd, List<MediaBatch> to, double toPpd) {
  final target = _majority(batch, to);
  return FlightCard(
    key: 'out-${batch.id}',
    batch: batch,
    fromDays: _daysOf(batch, fromPpd),
    toDays: target == null ? _daysOf(batch, fromPpd) : _daysOf(target, toPpd),
    fromY: batch.position.dy,
    toY: target == null ? batch.position.dy : target.position.dy,
    kind: FlightKind.mergeOut,
  );
}

FlightCard _settleIn(MediaBatch batch, double toPpd, List<MediaBatch> from, double fromPpd) {
  final source = _majority(batch, from);
  return FlightCard(
    key: 'in-${batch.id}',
    batch: batch,
    fromDays: source == null ? _daysOf(batch, toPpd) : _daysOf(source, fromPpd),
    toDays: _daysOf(batch, toPpd),
    fromY: source == null ? batch.position.dy : source.position.dy,
    toY: batch.position.dy,
    kind: FlightKind.fadeIn,
  );
}

FlightCard _fadeOut(MediaBatch batch, double ppd) {
  final days = _daysOf(batch, ppd);
  return FlightCard(
    key: 'out-${batch.id}',
    batch: batch,
    fromDays: days,
    toDays: days,
    fromY: batch.position.dy,
    toY: batch.position.dy,
    kind: FlightKind.fadeOut,
  );
}

FlightCard _splitIn(MediaBatch batch, double toPpd, List<MediaBatch> from, double fromPpd) {
  final parent = _parent(batch, from);
  return FlightCard(
    key: 'in-${batch.id}',
    batch: batch,
    fromDays: parent == null ? _daysOf(batch, toPpd) : _daysOf(parent, fromPpd),
    toDays: _daysOf(batch, toPpd),
    fromY: parent == null ? batch.position.dy : parent.position.dy,
    toY: batch.position.dy,
    kind: FlightKind.splitIn,
  );
}
