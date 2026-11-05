import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_asset.dart';
import '../models/media_filter.dart';
import 'image_loader.dart';
import 'media_probe.dart';
import 'thumbnail_cache.dart';

/// Shared folder scanner for macOS and Windows.
///
/// Reads shared_preferences `image_path`. When the key is missing or blank,
/// [defaultRoot] is the directory the app lives in (the platform loader
/// decides what that means for a .app bundle versus an .exe).
class DesktopLibrary {
  final Directory Function() defaultRoot;

  const DesktopLibrary({required this.defaultRoot});

  Future<String?> storedImagePath() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(imagePathPrefsKey)?.trim();
    if (stored == null || stored.isEmpty) return null;
    return stored;
  }

  Future<void> setImagePath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(imagePathPrefsKey);
    } else {
      await prefs.setString(imagePathPrefsKey, trimmed);
    }
  }

  Future<Directory> resolveRoot() async {
    final stored = await storedImagePath();
    if (stored == null) return defaultRoot();
    return Directory(stored);
  }

  Future<String> describeSource() async {
    final root = await resolveRoot();
    final stored = await storedImagePath();
    final suffix = stored == null ? '（默认，app 所在文件夹）' : '';
    return root.path + suffix;
  }

  Future<List<MediaAsset>> load({MediaFilter filter = const MediaFilter()}) async {
    final root = await resolveRoot();
    if (!await root.exists()) {
      throw LibraryException(
        '找不到文件夹：${root.path}\n'
        '在右上角写入 image_path，或把照片放进这个目录的子文件夹。',
      );
    }

    final found = <MediaAsset>[];
    await _walk(root, root, found, filter);
    found.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return found;
  }

  Future<void> _walk(
    Directory directory,
    Directory root,
    List<MediaAsset> into,
    MediaFilter filter,
  ) async {
    final List<FileSystemEntity> children;
    try {
      children = await directory.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }
    for (final entity in children) {
      if (entity is Directory) {
        if (_skipDirectory(p.basename(entity.path))) continue;
        await _walk(entity, root, into, filter);
      } else if (entity is File) {
        final asset = await _assetFromFile(entity);
        if (asset == null) continue;
        if (!filter.accepts(asset)) continue;
        into.add(asset);
      }
    }
  }

  bool _skipDirectory(String name) {
    const blocked = {
      '.git',
      '.dart_tool',
      'node_modules',
      'build',
      'Pods',
      'ephemeral',
      '.gradle',
      'DerivedData',
      '__pycache__',
    };
    return name.startsWith('.') || blocked.contains(name);
  }

  Future<MediaAsset?> _assetFromFile(File file) async {
    final extension = p.extension(file.path);
    final kind = kindForExtension(extension);
    if (kind == null) return null;
    final name = p.basename(file.path);
    if (name.startsWith('.')) return null;

    final stat = await file.stat();
    final header = await _readHead(file, 2 * 1024 * 1024);
    final probed = await probeHeader(header, extension);
    final captured = probed.capturedAt ?? stat.modified;

    return MediaAsset(
      id: file.path,
      filePath: file.path,
      fileName: name,
      kind: kind,
      mimeType: mimeForExtension(extension),
      fileSizeBytes: stat.size,
      width: probed.width,
      height: probed.height,
      duration: kind == MediaKind.video ? probed.duration : null,
      createdAt: captured,
      modifiedAt: stat.modified,
      albumName: p.basename(file.parent.path),
      camera: probed.camera,
      gps: probed.gps,
      thumbnailPath: await ThumbnailCache.existingPath(file.path),
    );
  }

  Future<Uint8List> _readHead(File file, int maxBytes) async {
    final length = await file.length();
    final take = length < maxBytes ? length : maxBytes;
    if (take <= 0) return Uint8List(0);
    final raf = await file.open();
    try {
      return await raf.read(take);
    } finally {
      await raf.close();
    }
  }

  Future<MediaAsset> ensureThumbnail(MediaAsset asset) async {
    if (asset.kind != MediaKind.image) return asset;
    if (asset.thumbnailBytes != null && asset.thumbnailBytes!.isNotEmpty) return asset;
    final cached = asset.thumbnailPath ?? await ThumbnailCache.existingPath(asset.id);
    if (cached != null && await File(cached).exists()) {
      return asset.thumbnailPath == cached ? asset : asset.copyWith(thumbnailPath: cached);
    }

    final file = File(asset.filePath);
    if (!await file.exists()) return asset;
    final length = await file.length();
    // Full decode of very large originals is not worth a hitch. Metadata still shows.
    if (length <= 0 || length > 18 * 1024 * 1024) return asset;
    final bytes = await file.readAsBytes();
    final jpeg = await compute(encodeThumbnailIsolate, bytes);
    if (jpeg == null || jpeg.isEmpty) return asset;
    final path = await ThumbnailCache.write(asset.id, jpeg);
    return asset.copyWith(thumbnailBytes: jpeg, thumbnailPath: path);
  }

  Future<MediaAsset> ensureDetails(MediaAsset asset) async => asset;
}
