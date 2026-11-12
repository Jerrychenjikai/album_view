import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/media_asset.dart';
import 'thumbnail_cache.dart';

/// Saved desktop scan for one folder. The next launch reads this instead of
/// walking the disk until the user asks to update.
class LibraryIndex {
  const LibraryIndex._();

  static Future<File> _file(String root) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'library-index'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, '${fnv1a64(root)}.json'));
  }

  static Future<List<MediaAsset>?> read(String root) async {
    try {
      final file = await _file(root);
      if (!await file.exists() || await file.length() <= 0) return null;
      final text = await file.readAsString();
      final decoded = await Isolate.run(() => jsonDecode(text));
      if (decoded is! Map || decoded['version'] != 1 || decoded['root'] != root) return null;
      final rawAssets = decoded['assets'];
      if (rawAssets is! List) return null;
      final assets = <MediaAsset>[];
      for (final raw in rawAssets) {
        final asset = MediaAsset.fromJson(raw);
        if (asset != null) assets.add(asset);
      }
      if (rawAssets.isNotEmpty && assets.isEmpty) return null;
      return assets;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String root, List<MediaAsset> assets) async {
    final payload = <String, Object?>{
      'version': 1,
      'root': root,
      'assets': [for (final asset in assets) asset.toJson()],
    };
    final text = await Isolate.run(() => jsonEncode(payload));
    final file = await _file(root);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }
}
