import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

part 'share_album.dart';
part 'share_board.dart';
part 'share_desk.dart';
part 'share_film.dart';
part 'share_frames.dart';
part 'share_gallery.dart';
part 'share_polaroid.dart';
part 'share_print.dart';

const int sharePhotoLimit = 100;

class ShareStyle {
  final String id;
  final String label;

  const ShareStyle(this.id, this.label);
}

/// Swiping the preview walks this list.
const List<ShareStyle> shareStyles = [
  ShareStyle('desk', '木桌'),
  ShareStyle('board', '公告板'),
  ShareStyle('gallery', '画廊'),
  ShareStyle('album', '相簿'),
  ShareStyle('frames', '相框'),
  ShareStyle('film', '胶片'),
  ShareStyle('polaroid', '拍立得'),
];

class _Slot {
  final double x;
  final double y;
  final double w;
  final double rot;
  final bool mark;

  const _Slot(this.x, this.y, this.w, this.rot, {this.mark = false});
}

class _Style {
  final String asset;
  final double saturate;
  final Color frame;
  final Color? frameEnd;
  final Color ink;
  final bool pins;
  final double lie;
  final bool gallery;
  final double grain;
  final double pad;
  final double foot;
  final double warm;
  final bool frames;
  final bool film;
  final bool polaroid;
  final List<List<_Slot>> layouts;

  const _Style({
    required this.asset,
    required this.saturate,
    required this.frame,
    required this.ink,
    required this.pins,
    required this.layouts,
    this.frameEnd,
    this.lie = 0,
    this.gallery = false,
    this.grain = 0,
    this.pad = 0.065,
    this.foot = 0.2,
    this.warm = 0,
    this.frames = false,
    this.film = false,
    this.polaroid = false,
  });
}

const Map<String, _Style> _styles = {
  'desk': _deskStyle,
  'board': _boardStyle,
  'gallery': _galleryStyle,
  'album': _albumStyle,
  'frames': _framesStyle,
  'film': _filmStyle,
  'polaroid': _polaroidStyle,
};

final Map<String, ui.Image> _backgrounds = {};

Future<ui.Image> _background(String asset) async {
  final cached = _backgrounds[asset];
  if (cached != null) return cached;
  final data = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  _backgrounds[asset] = frame.image;
  return frame.image;
}

Future<ui.Image?> _decode(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}

List<double> _saturation(double s) {
  const r = 0.2126;
  const g = 0.7152;
  const b = 0.0722;
  final sr = (1 - s) * r;
  final sg = (1 - s) * g;
  final sb = (1 - s) * b;
  return [
    sr + s, sg, sb, 0, 0,
    sr, sg + s, sb, 0, 0,
    sr, sg, sb + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

List<int> _occupiedSpots(int count) {
  if (count <= 0) return const [];
  if (count == 1) return const [1];
  if (count == 2) return const [0, 1];
  return const [0, 1, 2];
}

/// Draws up to three prints on the chosen share background.
Future<Uint8List> composeShareCard(List<Uint8List> photos, {String styleId = 'desk'}) async {
  final style = _styles[styleId];
  if (style == null) {
    throw StateError('还没有这个风格');
  }
  final decoded = <ui.Image>[];
  for (final bytes in photos.take(3)) {
    final image = await _decode(bytes);
    if (image != null) decoded.add(image);
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  late final double cw;
  late final double ch;
  ui.Image? backImage;
  if (style.film) {
    cw = _filmW;
    ch = _filmH;
  } else {
    final back = await _background(style.asset);
    backImage = back;
    canvas.drawImage(back, Offset.zero, Paint());
    cw = back.width.toDouble();
    ch = back.height.toDouble();
  }
  final warmed = <ui.Image>[];
  if (style.film) {
    await _paintFilm(canvas, cw, ch, decoded, style);
  } else if (style.polaroid) {
    _paintPolaroidDesk(canvas, backImage!, decoded, style);
  } else if (style.gallery) {
    _paintGallery(canvas, cw, ch, decoded, style);
  } else if (style.frames) {
    warmed.addAll(await _paintFrames(canvas, cw, ch, decoded, style));
  } else if (decoded.isNotEmpty) {
    final grain = style.grain > 0 ? await _grainImage() : null;
    await _paintPrints(canvas, cw, ch, decoded, style, grain);
  }
  final picture = recorder.endRecording();
  final out = await picture.toImage(cw.round(), ch.round());
  picture.dispose();
  for (final image in decoded) {
    image.dispose();
  }
  for (final image in warmed) {
    image.dispose();
  }
  final raw = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  final width = out.width;
  final height = out.height;
  out.dispose();
  if (raw == null) return Uint8List(0);
  final tight = Uint8List(width * height * 4);
  tight.setRange(0, tight.length, raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes));
  final encoded = img.encodeJpg(
    img.Image.fromBytes(
      width: width,
      height: height,
      bytes: tight.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    ),
    quality: 88,
  );
  return encoded is Uint8List ? encoded : Uint8List.fromList(encoded);
}
