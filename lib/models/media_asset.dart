import 'dart:math' as math;
import 'dart:typed_data';

enum MediaKind { image, video }

/// Lens, body and exposure read from EXIF or the platform library.
class CameraInfo {
  final String? make;
  final String? model;
  final String? lensMake;
  final String? lensModel;
  final double? focalLengthMm;
  final double? focalLength35mm;
  final double? aperture;
  final int? iso;
  final double? exposureSeconds;

  /// EXIF orientation 1–8. Null when the file has none.
  final int? exifOrientation;

  const CameraInfo({
    this.make,
    this.model,
    this.lensMake,
    this.lensModel,
    this.focalLengthMm,
    this.focalLength35mm,
    this.aperture,
    this.iso,
    this.exposureSeconds,
    this.exifOrientation,
  });

  static const empty = CameraInfo();

  bool get isEmpty =>
      make == null &&
      model == null &&
      lensMake == null &&
      lensModel == null &&
      focalLengthMm == null &&
      focalLength35mm == null &&
      aperture == null &&
      iso == null &&
      exposureSeconds == null;

  String get bodyLabel {
    final parts = <String>[
      if (make != null && make!.trim().isNotEmpty) make!.trim(),
      if (model != null && model!.trim().isNotEmpty) model!.trim(),
    ];
    if (parts.isEmpty) return '未知机身';
    if (parts.length == 2 && parts[1].toLowerCase().startsWith(parts[0].toLowerCase())) {
      return parts[1];
    }
    return parts.join(' ');
  }

  String get lensLabel {
    final lens = lensModel?.trim();
    if (lens != null && lens.isNotEmpty) return lens;
    final makeOnly = lensMake?.trim();
    if (makeOnly != null && makeOnly.isNotEmpty) return makeOnly;
    return '未知镜头';
  }

  String get exposureLabel {
    final bits = <String>[
      if (focalLengthMm != null) '${_trimNum(focalLengthMm!)} mm',
      if (aperture != null) 'f/${_trimNum(aperture!)}',
      if (exposureSeconds != null) _shutter(exposureSeconds!),
      if (iso != null) 'ISO $iso',
    ];
    return bits.isEmpty ? '无曝光信息' : bits.join('  ·  ');
  }

  Map<String, Object?> toJson() => {
        'make': make,
        'model': model,
        'lensMake': lensMake,
        'lensModel': lensModel,
        'focalLengthMm': focalLengthMm,
        'focalLength35mm': focalLength35mm,
        'aperture': aperture,
        'iso': iso,
        'exposureSeconds': exposureSeconds,
        'exifOrientation': exifOrientation,
      };

  static CameraInfo fromJson(Object? raw) {
    if (raw is! Map) return CameraInfo.empty;
    return CameraInfo(
      make: raw['make'] as String?,
      model: raw['model'] as String?,
      lensMake: raw['lensMake'] as String?,
      lensModel: raw['lensModel'] as String?,
      focalLengthMm: (raw['focalLengthMm'] as num?)?.toDouble(),
      focalLength35mm: (raw['focalLength35mm'] as num?)?.toDouble(),
      aperture: (raw['aperture'] as num?)?.toDouble(),
      iso: (raw['iso'] as num?)?.toInt(),
      exposureSeconds: (raw['exposureSeconds'] as num?)?.toDouble(),
      exifOrientation: (raw['exifOrientation'] as num?)?.toInt(),
    );
  }
}

String _trimNum(double value) {
  if ((value - value.round()).abs() < 0.05) return value.round().toString();
  return value.toStringAsFixed(1);
}

String _shutter(double seconds) {
  if (seconds <= 0) return '—';
  if (seconds >= 1) return '${_trimNum(seconds)} s';
  final denom = (1 / seconds).round();
  return '1/$denom s';
}

class GpsInfo {
  final double latitude;
  final double longitude;
  final double? altitude;

  /// City, or a longer place string. Only the city is shown on a batch.
  final String? city;

  const GpsInfo({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.city,
  });

  String get label {
    final named = cityName;
    if (named != null) return named;
    final lat = latitude.toStringAsFixed(5);
    final lng = longitude.toStringAsFixed(5);
    if (altitude == null) return '$lat, $lng';
    return '$lat, $lng  ·  ${altitude!.toStringAsFixed(0)} m';
  }

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': altitude,
        'city': city,
      };

  static GpsInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final latitude = raw['latitude'];
    final longitude = raw['longitude'];
    if (latitude is! num || longitude is! num) return null;
    return GpsInfo(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      altitude: (raw['altitude'] as num?)?.toDouble(),
      city: raw['city'] as String?,
    );
  }

  /// City only. A stored "street, city, region" keeps the city token.
  String? get cityName {
    final named = city?.trim();
    if (named != null && named.isNotEmpty) return cityToken(named);
    return nearestCity(latitude, longitude);
  }
}

/// First non-street, non-region piece of a place string.
String? cityToken(String raw) {
  final parts = raw.split(RegExp(r'[,，]')).map((part) => part.trim()).where((part) => part.isNotEmpty);
  const admin = {
    'canada',
    'ontario',
    'quebec',
    '中国',
    '美国',
    '加拿大',
    '安大略',
    'usa',
    'uk',
    'china',
  };
  for (final part in parts) {
    if (RegExp(r'\d').hasMatch(part)) continue;
    if (admin.contains(part.toLowerCase())) continue;
    if (RegExp(r'(street|st\.|avenue|ave\.|road|rd\.|路|街|道)$', caseSensitive: false).hasMatch(part)) {
      continue;
    }
    return part;
  }
  return null;
}

const List<({String name, double lat, double lng})> _knownCities = [
  (name: '多伦多', lat: 43.6532, lng: -79.3832),
  (name: '密西沙加', lat: 43.5890, lng: -79.6441),
  (name: '纽马克特', lat: 44.0592, lng: -79.4613),
  (name: '巴里', lat: 44.3894, lng: -79.6903),
  (name: '彼得伯勒', lat: 44.3091, lng: -78.3197),
  (name: '金斯顿', lat: 44.2312, lng: -76.4860),
  (name: '渥太华', lat: 45.4215, lng: -75.6972),
  (name: '蒙特利尔', lat: 45.5017, lng: -73.5673),
  (name: '温哥华', lat: 49.2827, lng: -123.1207),
  (name: '北京', lat: 39.9042, lng: 116.4074),
  (name: '上海', lat: 31.2304, lng: 121.4737),
  (name: '东京', lat: 35.6762, lng: 139.6503),
  (name: '纽约', lat: 40.7128, lng: -74.0060),
  (name: '伦敦', lat: 51.5074, lng: -0.1278),
  (name: '巴黎', lat: 48.8566, lng: 2.3522),
];

String? nearestCity(double latitude, double longitude) {
  String? best;
  var bestKm = 80.0;
  for (final city in _knownCities) {
    final km = _haversineKm(latitude, longitude, city.lat, city.lng);
    if (km < bestKm) {
      bestKm = km;
      best = city.name;
    }
  }
  return best;
}

double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const earth = 6371.0;
  final r1 = lat1 * math.pi / 180;
  final r2 = lat2 * math.pi / 180;
  final dLat = (lat2 - lat1) * math.pi / 180;
  final dLng = (lng2 - lng1) * math.pi / 180;
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(r1) * math.cos(r2) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earth * math.asin(math.min(1, math.sqrt(h.toDouble())));
}

/// One still or one video on disk / in the system photo library.
class MediaAsset {
  final String id;
  final String filePath;
  final String fileName;
  final MediaKind kind;
  final String? mimeType;
  final int? fileSizeBytes;
  final int? width;
  final int? height;

  /// Clockwise quarter-turns reported by the platform (Android MediaStore).
  /// EXIF orientation, when present, wins for [swapsAxes].
  final int rotationDegrees;
  final Duration? duration;
  final DateTime createdAt;
  final DateTime? modifiedAt;

  /// Parent folder name, or the system album title.
  final String? albumName;
  final CameraInfo camera;
  final GpsInfo? gps;

  /// JPEG (or PNG) bytes of a small preview. Null until generated.
  final Uint8List? thumbnailBytes;

  /// On-disk cache of [thumbnailBytes], when written.
  final String? thumbnailPath;

  const MediaAsset({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.kind,
    required this.createdAt,
    this.mimeType,
    this.fileSizeBytes,
    this.width,
    this.height,
    this.rotationDegrees = 0,
    this.duration,
    this.modifiedAt,
    this.albumName,
    this.camera = CameraInfo.empty,
    this.gps,
    this.thumbnailBytes,
    this.thumbnailPath,
  });

  bool get swapsAxes {
    final orientation = camera.exifOrientation;
    if (orientation != null) return orientation >= 5 && orientation <= 8;
    return rotationDegrees % 180 == 90;
  }

  int? get orientedWidth => swapsAxes ? height : width;
  int? get orientedHeight => swapsAxes ? width : height;

  String get resolutionLabel {
    final w = orientedWidth;
    final h = orientedHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return '未知';
    return '$w×$h';
  }

  String get fileSizeLabel {
    final bytes = fileSizeBytes;
    if (bytes == null || bytes < 0) return '未知';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get durationLabel {
    final value = duration;
    if (value == null || kind != MediaKind.video) return '';
    final total = value.inSeconds;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  bool get hasThumbnail =>
      (thumbnailBytes != null && thumbnailBytes!.isNotEmpty) ||
      (thumbnailPath != null && thumbnailPath!.isNotEmpty);

  MediaAsset copyWith({
    String? filePath,
    String? fileName,
    String? mimeType,
    int? fileSizeBytes,
    int? width,
    int? height,
    int? rotationDegrees,
    Duration? duration,
    DateTime? modifiedAt,
    String? albumName,
    CameraInfo? camera,
    GpsInfo? gps,
    bool writeGps = false,
    Uint8List? thumbnailBytes,
    String? thumbnailPath,
    bool writeThumbnailBytes = false,
    bool writeThumbnailPath = false,
  }) {
    return MediaAsset(
      id: id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      kind: kind,
      createdAt: createdAt,
      mimeType: mimeType ?? this.mimeType,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      duration: duration ?? this.duration,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      albumName: albumName ?? this.albumName,
      camera: camera ?? this.camera,
      gps: writeGps ? gps : (gps ?? this.gps),
      thumbnailBytes: writeThumbnailBytes ? thumbnailBytes : (thumbnailBytes ?? this.thumbnailBytes),
      thumbnailPath: writeThumbnailPath ? thumbnailPath : (thumbnailPath ?? this.thumbnailPath),
    );
  }

  /// Persistent fields. Thumbnail bytes stay out: they are a runtime preview.
  Map<String, Object?> toJson() => {
        'id': id,
        'filePath': filePath,
        'fileName': fileName,
        'kind': kind.name,
        'mimeType': mimeType,
        'fileSizeBytes': fileSizeBytes,
        'width': width,
        'height': height,
        'rotationDegrees': rotationDegrees,
        'durationMs': duration?.inMilliseconds,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'modifiedAt': modifiedAt?.millisecondsSinceEpoch,
        'albumName': albumName,
        'camera': camera.toJson(),
        'gps': gps?.toJson(),
        'thumbnailPath': thumbnailPath,
      };

  static MediaAsset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final filePath = raw['filePath'];
    final fileName = raw['fileName'];
    final created = raw['createdAt'];
    if (id is! String || filePath is! String || fileName is! String || created is! num) return null;
    final kindName = raw['kind'];
    final kind = kindName == 'video' ? MediaKind.video : MediaKind.image;
    final durationMs = raw['durationMs'];
    final modified = raw['modifiedAt'];
    return MediaAsset(
      id: id,
      filePath: filePath,
      fileName: fileName,
      kind: kind,
      createdAt: DateTime.fromMillisecondsSinceEpoch(created.toInt()),
      mimeType: raw['mimeType'] as String?,
      fileSizeBytes: (raw['fileSizeBytes'] as num?)?.toInt(),
      width: (raw['width'] as num?)?.toInt(),
      height: (raw['height'] as num?)?.toInt(),
      rotationDegrees: (raw['rotationDegrees'] as num?)?.toInt() ?? 0,
      duration: durationMs is num ? Duration(milliseconds: durationMs.toInt()) : null,
      modifiedAt: modified is num ? DateTime.fromMillisecondsSinceEpoch(modified.toInt()) : null,
      albumName: raw['albumName'] as String?,
      camera: CameraInfo.fromJson(raw['camera']),
      gps: GpsInfo.fromJson(raw['gps']),
      thumbnailPath: raw['thumbnailPath'] as String?,
    );
  }
}
