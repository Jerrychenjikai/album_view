import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

String fnv1a64(String input) {
  var hash = 0xcbf29ce484222325;
  for (final code in input.codeUnits) {
    hash ^= code;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

class ThumbnailCache {
  const ThumbnailCache._();

  static Future<Directory>? _directory;

  static Future<Directory> _dir() {
    return _directory ??= () async {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'thumbnails'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }();
  }

  static Future<File> fileFor(String assetId) async {
    final dir = await _dir();
    return File(p.join(dir.path, '${fnv1a64(assetId)}.jpg'));
  }

  static Future<String?> existingPath(String assetId) async {
    final file = await fileFor(assetId);
    if (await file.exists() && await file.length() > 0) return file.path;
    return null;
  }

  static Future<String> write(String assetId, Uint8List jpeg) async {
    final file = await fileFor(assetId);
    await file.writeAsBytes(jpeg, flush: true);
    return file.path;
  }
}

/// Isolate entry. Must stay a top-level function.
Uint8List? encodeThumbnailIsolate(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final img.Image sized;
    if (decoded.width <= 520 && decoded.height <= 520) {
      sized = decoded;
    } else if (decoded.width >= decoded.height) {
      sized = img.copyResize(decoded, width: 480, interpolation: img.Interpolation.linear);
    } else {
      sized = img.copyResize(decoded, height: 480, interpolation: img.Interpolation.linear);
    }
    return Uint8List.fromList(img.encodeJpg(sized, quality: 72));
  } catch (_) {
    return null;
  }
}
