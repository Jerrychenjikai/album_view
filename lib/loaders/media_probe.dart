import 'dart:typed_data';

import 'package:exif/exif.dart';

import '../models/media_asset.dart';

class ProbedMedia {
  final int? width;
  final int? height;
  final Duration? duration;
  final DateTime? capturedAt;
  final CameraInfo camera;
  final GpsInfo? gps;

  const ProbedMedia({
    this.width,
    this.height,
    this.duration,
    this.capturedAt,
    this.camera = CameraInfo.empty,
    this.gps,
  });

  static const empty = ProbedMedia();
}

const imageExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.heic',
  '.heif',
  '.bmp',
  '.tif',
  '.tiff',
  '.dng',
};

const videoExtensions = <String>{
  '.mp4',
  '.mov',
  '.m4v',
  '.avi',
  '.mkv',
  '.webm',
  '.3gp',
};

MediaKind? kindForExtension(String extension) {
  final ext = extension.toLowerCase();
  if (imageExtensions.contains(ext)) return MediaKind.image;
  if (videoExtensions.contains(ext)) return MediaKind.video;
  return null;
}

String? mimeForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.png':
      return 'image/png';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.heic':
      return 'image/heic';
    case '.heif':
      return 'image/heif';
    case '.bmp':
      return 'image/bmp';
    case '.tif':
    case '.tiff':
      return 'image/tiff';
    case '.dng':
      return 'image/x-adobe-dng';
    case '.mp4':
    case '.m4v':
      return 'video/mp4';
    case '.mov':
      return 'video/quicktime';
    case '.webm':
      return 'video/webm';
    case '.mkv':
      return 'video/x-matroska';
    case '.avi':
      return 'video/x-msvideo';
    case '.3gp':
      return 'video/3gpp';
    default:
      return null;
  }
}

/// Reads dimensions, duration and EXIF from the leading bytes of a file.
/// [header] should be at least the first 64 KB; 2 MB covers typical EXIF.
Future<ProbedMedia> probeHeader(Uint8List header, String extension) async {
  final ext = extension.toLowerCase();
  var width = _widthOf(header, ext);
  var height = _heightOf(header, ext);
  Duration? duration;
  DateTime? capturedAt;
  var camera = CameraInfo.empty;
  GpsInfo? gps;

  if (ext == '.mp4' || ext == '.mov' || ext == '.m4v' || ext == '.3gp') {
    final video = _probeIsoBmff(header);
    width ??= video.width;
    height ??= video.height;
    duration = video.duration;
    capturedAt = video.capturedAt;
  } else if (ext == '.heic' || ext == '.heif') {
    final (stillWidth, stillHeight) = _probeIspe(header);
    width ??= stillWidth;
    height ??= stillHeight;
  }

  if (ext == '.jpg' || ext == '.jpeg' || ext == '.tif' || ext == '.tiff') {
    try {
      final tags = await readExifFromBytes(header, strict: false);
      final parsed = _exifFromTags(tags);
      width ??= parsed.width;
      height ??= parsed.height;
      capturedAt ??= parsed.capturedAt;
      camera = parsed.camera;
      gps = parsed.gps;
    } catch (_) {
      // Truncated or non-EXIF payloads still keep the header dimensions.
    }
  }

  return ProbedMedia(
    width: width,
    height: height,
    duration: duration,
    capturedAt: capturedAt,
    camera: camera,
    gps: gps,
  );
}

int? _widthOf(Uint8List bytes, String ext) => _sizeOf(bytes, ext)?.$1;
int? _heightOf(Uint8List bytes, String ext) => _sizeOf(bytes, ext)?.$2;

(int, int)? _sizeOf(Uint8List bytes, String ext) {
  if (ext == '.jpg' || ext == '.jpeg') return _jpegSize(bytes);
  if (ext == '.png') return _pngSize(bytes);
  if (ext == '.gif') return _gifSize(bytes);
  if (ext == '.bmp') return _bmpSize(bytes);
  if (ext == '.webp') return _webpSize(bytes);
  if (ext == '.tif' || ext == '.tiff' || ext == '.dng') return _tiffSize(bytes);
  return null;
}

(int, int)? _jpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var i = 2;
  while (i + 8 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    while (i < bytes.length && bytes[i] == 0xFF) {
      i++;
    }
    if (i >= bytes.length) break;
    final marker = bytes[i];
    i++;
    if (marker == 0xD8) continue;
    if (marker == 0xD9 || marker == 0xDA) break;
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) continue;
    if (i + 1 >= bytes.length) break;
    final length = (bytes[i] << 8) | bytes[i + 1];
    if (length < 2 || i + length > bytes.length) break;
    const sof = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB};
    if (sof.contains(marker) && i + 6 < bytes.length) {
      final height = (bytes[i + 3] << 8) | bytes[i + 4];
      final width = (bytes[i + 5] << 8) | bytes[i + 6];
      if (width > 0 && height > 0) return (width, height);
    }
    i += length;
  }
  return null;
}

(int, int)? _pngSize(Uint8List bytes) {
  if (bytes.length < 24) return null;
  const sig = [0x89, 0x50, 0x4E, 0x47];
  for (var i = 0; i < 4; i++) {
    if (bytes[i] != sig[i]) return null;
  }
  final width = _u32(bytes, 16);
  final height = _u32(bytes, 20);
  if (width <= 0 || height <= 0) return null;
  return (width, height);
}

(int, int)? _gifSize(Uint8List bytes) {
  if (bytes.length < 10) return null;
  final head = String.fromCharCodes(bytes.sublist(0, 3));
  if (head != 'GIF') return null;
  final width = bytes[6] | (bytes[7] << 8);
  final height = bytes[8] | (bytes[9] << 8);
  if (width <= 0 || height <= 0) return null;
  return (width, height);
}

(int, int)? _bmpSize(Uint8List bytes) {
  if (bytes.length < 26 || bytes[0] != 0x42 || bytes[1] != 0x4D) return null;
  final width = _i32(bytes, 18).abs();
  final height = _i32(bytes, 22).abs();
  if (width <= 0 || height <= 0) return null;
  return (width, height);
}

(int, int)? _webpSize(Uint8List bytes) {
  if (bytes.length < 30) return null;
  if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
  if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WEBP') return null;
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final type = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = _u32le(bytes, offset + 4);
    final data = offset + 8;
    if (type == 'VP8X' && data + 10 <= bytes.length) {
      final width = 1 + (bytes[data + 4] | (bytes[data + 5] << 8) | (bytes[data + 6] << 16));
      final height = 1 + (bytes[data + 7] | (bytes[data + 8] << 8) | (bytes[data + 9] << 16));
      if (width > 0 && height > 0) return (width, height);
    }
    if (type == 'VP8 ' && data + 10 <= bytes.length) {
      final found = _indexOf(bytes, const [0x9D, 0x01, 0x2A], data);
      if (found >= 0 && found + 7 <= bytes.length) {
        final width = (bytes[found + 3] | (bytes[found + 4] << 8)) & 0x3FFF;
        final height = (bytes[found + 5] | (bytes[found + 6] << 8)) & 0x3FFF;
        if (width > 0 && height > 0) return (width, height);
      }
    }
    if (size <= 0) break;
    offset = data + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

(int, int)? _tiffSize(Uint8List bytes) {
  if (bytes.length < 8) return null;
  final little = bytes[0] == 0x49 && bytes[1] == 0x49;
  final big = bytes[0] == 0x4D && bytes[1] == 0x4D;
  if (!little && !big) return null;
  int u16(int o) => little ? bytes[o] | (bytes[o + 1] << 8) : (bytes[o] << 8) | bytes[o + 1];
  int u32(int o) => little ? _u32le(bytes, o) : _u32(bytes, o);
  if (u16(2) != 42) return null;
  final ifd = u32(4);
  if (ifd <= 0 || ifd + 2 >= bytes.length) return null;
  final count = u16(ifd);
  int? width;
  int? height;
  for (var entry = 0; entry < count; entry++) {
    final at = ifd + 2 + entry * 12;
    if (at + 12 > bytes.length) break;
    final tag = u16(at);
    final value = u32(at + 8);
    if (tag == 256) width = value;
    if (tag == 257) height = value;
  }
  if (width == null || height == null || width <= 0 || height <= 0) return null;
  return (width, height);
}

class _VideoProbe {
  final int? width;
  final int? height;
  final Duration? duration;
  final DateTime? capturedAt;
  const _VideoProbe({this.width, this.height, this.duration, this.capturedAt});
}

_VideoProbe _probeIsoBmff(Uint8List bytes) {
  int? width;
  int? height;
  int? timescale;
  int? durationUnits;
  int? creationSeconds;

  void walk(int start, int end) {
    var cursor = start;
    while (cursor + 8 <= end && cursor + 8 <= bytes.length) {
      var size = _u32(bytes, cursor);
      final type = String.fromCharCodes(bytes.sublist(cursor + 4, cursor + 8));
      var header = 8;
      if (size == 1) {
        if (cursor + 16 > bytes.length) break;
        size = _u64(bytes, cursor + 8);
        header = 16;
      } else if (size == 0) {
        size = end - cursor;
      }
      if (size < header) break;
      final contentStart = cursor + header;
      final contentEnd = cursor + size;
      final limit = contentEnd > bytes.length ? bytes.length : contentEnd;
      if (type == 'moov' || type == 'trak' || type == 'mdia') {
        walk(contentStart, limit);
      } else if (type == 'mvhd' && contentStart + 20 < limit) {
        final version = bytes[contentStart];
        if (version == 1 && contentStart + 32 <= limit) {
          creationSeconds ??= _u64(bytes, contentStart + 4);
          timescale = _u32(bytes, contentStart + 20);
          durationUnits = _u64(bytes, contentStart + 24);
        } else if (contentStart + 20 <= limit) {
          creationSeconds ??= _u32(bytes, contentStart + 4);
          timescale = _u32(bytes, contentStart + 12);
          durationUnits = _u32(bytes, contentStart + 16);
        }
      } else if (type == 'tkhd' && limit - contentStart >= 8) {
        final rawW = _u32(bytes, limit - 8) / 65536.0;
        final rawH = _u32(bytes, limit - 4) / 65536.0;
        final w = rawW.round();
        final h = rawH.round();
        if (w > 0 && h > 0 && (width == null || w * h > (width! * (height ?? 0)))) {
          width = w;
          height = h;
        }
      }
      if (contentEnd <= cursor) break;
      cursor = contentEnd;
      if (cursor > bytes.length) break;
    }
  }

  walk(0, bytes.length);
  Duration? duration;
  if (timescale != null && timescale! > 0 && durationUnits != null && durationUnits! > 0) {
    duration = Duration(milliseconds: (durationUnits! * 1000 / timescale!).round());
  }
  return _VideoProbe(
    width: width,
    height: height,
    duration: duration,
    capturedAt: _macEpoch(creationSeconds),
  );
}

(int?, int?) _probeIspe(Uint8List bytes) {
  int? width;
  int? height;

  void consider(int contentStart, int contentEnd) {
    if (contentStart + 12 > bytes.length || contentStart + 12 > contentEnd) return;
    final w = _u32(bytes, contentStart + 4);
    final h = _u32(bytes, contentStart + 8);
    if (w > 0 && h > 0 && width == null) {
      width = w;
      height = h;
    }
  }

  void walk(int start, int end, {bool insideMeta = false}) {
    var cursor = start;
    while (cursor + 8 <= end && cursor + 8 <= bytes.length) {
      var size = _u32(bytes, cursor);
      final type = String.fromCharCodes(bytes.sublist(cursor + 4, cursor + 8));
      var header = 8;
      if (size == 1) {
        if (cursor + 16 > bytes.length) break;
        size = _u64(bytes, cursor + 8);
        header = 16;
      } else if (size == 0) {
        size = end - cursor;
      }
      if (size < header) break;
      final contentStart = cursor + header;
      final contentEnd = cursor + size;
      final limit = contentEnd > bytes.length ? bytes.length : contentEnd;
      if (type == 'meta') {
        final child = contentStart + 4;
        if (child < limit) walk(child, limit, insideMeta: true);
      } else if (type == 'iprp' || type == 'ipco') {
        walk(contentStart, limit, insideMeta: insideMeta);
      } else if (type == 'ispe') {
        consider(contentStart, limit);
      }
      if (contentEnd <= cursor) break;
      cursor = contentEnd;
    }
  }

  walk(0, bytes.length);
  return (width, height);
}

class _ExifParsed {
  final int? width;
  final int? height;
  final DateTime? capturedAt;
  final CameraInfo camera;
  final GpsInfo? gps;
  const _ExifParsed({
    this.width,
    this.height,
    this.capturedAt,
    this.camera = CameraInfo.empty,
    this.gps,
  });
}

_ExifParsed _exifFromTags(Map<String, IfdTag> tags) {
  String? text(List<String> names) {
    final tag = _findTag(tags, names);
    final value = tag?.printable.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  double? number(List<String> names) {
    final value = text(names);
    if (value == null) return null;
    return parseLeadingNumber(value);
  }

  final captured = parseExifDate(
    text(const ['EXIF DateTimeOriginal', 'Image DateTime', 'EXIF DateTimeDigitized']),
  );
  final orientation = number(const ['Image Orientation'])?.round();
  final iso = number(const ['EXIF ISOSpeedRatings', 'EXIF PhotographicSensitivity'])?.round();

  return _ExifParsed(
    width: number(const ['EXIF ExifImageWidth', 'Image ImageWidth'])?.round(),
    height: number(const ['EXIF ExifImageLength', 'Image ImageLength'])?.round(),
    capturedAt: captured,
    camera: CameraInfo(
      make: text(const ['Image Make']),
      model: text(const ['Image Model']),
      lensMake: text(const ['EXIF LensMake']),
      lensModel: text(const ['EXIF LensModel']),
      focalLengthMm: number(const ['EXIF FocalLength']),
      focalLength35mm: number(const ['EXIF FocalLengthIn35mmFilm']),
      aperture: number(const ['EXIF FNumber']),
      iso: iso,
      exposureSeconds: number(const ['EXIF ExposureTime']),
      exifOrientation: orientation,
    ),
    gps: parseGpsTags(
      text(const ['GPS GPSLatitude']),
      text(const ['GPS GPSLatitudeRef']),
      text(const ['GPS GPSLongitude']),
      text(const ['GPS GPSLongitudeRef']),
      number(const ['GPS GPSAltitude']),
    ),
  );
}

IfdTag? _findTag(Map<String, IfdTag> tags, List<String> names) {
  if (tags.isEmpty) return null;
  final lower = <String, IfdTag>{};
  for (final entry in tags.entries) {
    lower[entry.key.toLowerCase()] = entry.value;
  }
  for (final name in names) {
    final found = lower[name.toLowerCase()];
    if (found != null) return found;
  }
  return null;
}

double? parseLeadingNumber(String printable) {
  final fraction = RegExp(r'([-+]?\d+(?:\.\d+)?)\s*/\s*([-+]?\d+(?:\.\d+)?)').firstMatch(printable);
  if (fraction != null) {
    final denominator = double.parse(fraction.group(2)!);
    if (denominator == 0) return null;
    return double.parse(fraction.group(1)!) / denominator;
  }
  final match = RegExp(r'[-+]?\d+(?:\.\d+)?').firstMatch(printable);
  if (match == null) return null;
  return double.parse(match.group(0)!);
}

DateTime? parseExifDate(String? printable) {
  if (printable == null) return null;
  final match = RegExp(r'(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})').firstMatch(printable);
  if (match == null) return null;
  final date = DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
  final latest = DateTime.now().add(const Duration(days: 2));
  if (date.year < 1975 || date.isAfter(latest)) return null;
  return date;
}

GpsInfo? parseGpsTags(
  String? latitude,
  String? latitudeRef,
  String? longitude,
  String? longitudeRef,
  double? altitude,
) {
  final lat = parseDms(latitude, latitudeRef);
  final lng = parseDms(longitude, longitudeRef);
  if (lat == null || lng == null) return null;
  if (lat.abs() > 90 || lng.abs() > 180) return null;
  if (lat == 0 && lng == 0) return null;
  return GpsInfo(latitude: lat, longitude: lng, altitude: altitude);
}

double? parseDms(String? printable, String? ref) {
  if (printable == null || printable.trim().isEmpty) return null;
  final pieces = printable.split(RegExp(r'[,;\[\]]')).map((part) => part.trim()).where((part) => part.isNotEmpty);
  final numbers = <double>[];
  for (final piece in pieces) {
    final value = parseLeadingNumber(piece);
    if (value != null) numbers.add(value);
  }
  if (numbers.isEmpty) {
    final value = parseLeadingNumber(printable);
    if (value == null) return null;
    numbers.add(value);
  }
  var degrees = numbers.first;
  if (numbers.length >= 3) {
    degrees = numbers[0] + numbers[1] / 60 + numbers[2] / 3600;
  } else if (numbers.length == 2) {
    degrees = numbers[0] + numbers[1] / 60;
  }
  final mark = (ref ?? '').trim().toUpperCase();
  if (mark.startsWith('S') || mark.startsWith('W')) degrees = -degrees.abs();
  return degrees;
}

DateTime? _macEpoch(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  final date = DateTime.utc(1904, 1, 1).add(Duration(seconds: seconds));
  if (date.year < 1975 || date.year > 2100) return null;
  return date.toLocal();
}

int _u32(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
}

int _u32le(Uint8List bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
}

int _i32(Uint8List bytes, int offset) => _u32le(bytes, offset).toSigned(32);

int _u64(Uint8List bytes, int offset) {
  final hi = _u32(bytes, offset);
  final lo = _u32(bytes, offset + 4);
  return (hi << 32) | lo;
}

int _indexOf(Uint8List bytes, List<int> needle, int from) {
  final last = bytes.length - needle.length;
  for (var i = from; i <= last; i++) {
    var matched = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        matched = false;
        break;
      }
    }
    if (matched) return i;
  }
  return -1;
}
