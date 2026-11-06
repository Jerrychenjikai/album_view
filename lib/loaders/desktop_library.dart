import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_asset.dart';
import '../models/media_filter.dart';
import 'image_loader.dart';
import 'media_probe.dart';
import 'still_thumb.dart';
import 'thumbnail_cache.dart';
import 'windows_thumb.dart';

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
    final suffix = stored == null ? '（默认）' : '';
    return root.path + suffix;
  }

  Future<List<MediaAsset>> load({
    MediaFilter filter = const MediaFilter(),
    void Function(List<MediaAsset> batch)? onBatch,
    void Function(LoadProgress progress)? onProgress,
  }) async {
    final root = await resolveRoot();
    if (!await root.exists()) {
      throw LibraryException(
        '找不到文件夹：${root.path}\n'
        '点「来源」写一个照片文件夹，或把照片放进这个目录。',
      );
    }

    final files = <File>[];
    onProgress?.call(LoadProgress(done: 0, total: 0, counting: true));
    await _collect(root, root, files, (seen) {
      onProgress?.call(LoadProgress(done: seen, total: 0, counting: true));
    });
    final total = files.length;
    onProgress?.call(LoadProgress(done: 0, total: total));

    final found = <MediaAsset>[];
    final pending = <MediaAsset>[];
    for (var index = 0; index < files.length; index++) {
      final asset = await _assetFromFile(files[index]);
      if (asset != null && filter.accepts(asset)) {
        found.add(asset);
        pending.add(asset);
        if (pending.length >= 100) {
          onBatch?.call(List<MediaAsset>.from(pending));
          pending.clear();
        }
      }
      if (index % 6 == 0 || index == files.length - 1) {
        onProgress?.call(LoadProgress(done: index + 1, total: total));
      }
    }
    if (pending.isNotEmpty) onBatch?.call(List<MediaAsset>.from(pending));
    found.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    onProgress?.call(LoadProgress(done: total, total: total));
    return found;
  }

  Future<void> _collect(
    Directory root,
    Directory directory,
    List<File> files,
    void Function(int seen) onSeen,
  ) async {
    final List<FileSystemEntity> children;
    try {
      children = await directory.list(followLinks: false).toList();
    } on FileSystemException catch (error) {
      if (directory.path == root.path) {
        final detail = error.osError?.message ?? error.message;
        final hint = Platform.isMacOS ? ' 请点「来源」，在系统弹窗里重新选一次。' : '';
        throw LibraryException('无法读取文件夹：${directory.path} $detail$hint');
      }
      return;
    }
    var visited = 0;
    for (final entity in children) {
      visited++;
      if (entity is Directory) {
        if (_skipDirectory(p.basename(entity.path))) continue;
        await _collect(root, entity, files, onSeen);
      } else if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('.')) continue;
        if (kindForExtension(p.extension(entity.path)) == null) continue;
        files.add(entity);
      }
      if (visited % 24 == 0) {
        onSeen(files.length);
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (directory.path == root.path) onSeen(files.length);
  }

  bool _skipDirectory(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.app') ||
        lower.endsWith('.photoslibrary') ||
        lower.endsWith('.framework') ||
        lower.endsWith('.bundle')) {
      return true;
    }
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
    try {
      return await _readAsset(file);
    } catch (_) {
      return null;
    }
  }

  Future<MediaAsset?> _readAsset(File file) async {
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
    if (asset.thumbnailBytes != null && asset.thumbnailBytes!.isNotEmpty) return asset;
    final cached = asset.thumbnailPath ?? await ThumbnailCache.existingPath(asset.id);
    if (cached != null && await File(cached).exists()) {
      return asset.thumbnailPath == cached ? asset : asset.copyWith(thumbnailPath: cached);
    }

    final file = File(asset.filePath);
    if (!await file.exists()) return asset;

    Uint8List? jpeg;
    if (asset.kind == MediaKind.image) {
      jpeg = await stillThumbnail(file.path);
    }
    // Windows has no frame grabber of its own here. The shell thumbnail is
    // what Explorer shows for mp4/mov, and it also covers HEIC the engine
    // cannot decode. It runs off the UI isolate.
    if ((jpeg == null || jpeg.isEmpty) && Platform.isWindows) {
      jpeg = await windowsFileThumbnail(file.path);
    }
    if (jpeg == null || jpeg.isEmpty) return asset;
    final path = await ThumbnailCache.write(asset.id, jpeg);
    return asset.copyWith(
      thumbnailBytes: null,
      writeThumbnailBytes: true,
      thumbnailPath: path,
      writeThumbnailPath: true,
    );
  }

  Future<MediaAsset> ensureDetails(MediaAsset asset) async => asset;

  Future<String?> materializeOriginal(MediaAsset asset) async {
    final file = File(asset.filePath);
    if (await file.exists()) return file.path;
    return null;
  }

  Future<void> reveal(MediaAsset asset) async {
    final file = File(asset.filePath);
    if (!await file.exists()) throw const LibraryException('找不到这个文件');
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,${file.path}']);
      return;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', ['-R', file.path]);
      if (result.exitCode != 0) throw const LibraryException('无法在访达中显示');
      return;
    }
    final result = await Process.run('xdg-open', [file.parent.path]);
    if (result.exitCode != 0) throw const LibraryException('无法打开所在文件夹');
  }
}
