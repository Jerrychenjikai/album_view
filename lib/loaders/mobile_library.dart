import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/media_asset.dart';
import '../models/media_filter.dart';
import 'image_loader.dart';
import 'media_probe.dart';

/// System photo library reader shared by the iOS and Android loaders.
///
/// Uses the single "all photos" album so items are not duplicated across
/// user albums. Date bounds in [MediaFilter] are pushed into PhotoManager;
/// kind, GPS and name filters are applied again in Dart.
class MobileLibrary {
  const MobileLibrary();

  Future<List<MediaAsset>> load({
    MediaFilter filter = const MediaFilter(),
    void Function(List<MediaAsset> batch)? onBatch,
    void Function(LoadProgress progress)? onProgress,
  }) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!_hasAccess(permission)) {
      throw const LibraryException('没有相册访问权限。请在系统设置中允许后点重新读取。');
    }

    final option = FilterOptionGroup(
      imageOption: const FilterOption(needTitle: true),
      videoOption: const FilterOption(needTitle: true),
      createTimeCond: filter.hasDateSpan
          ? DateTimeCond(
              min: filter.startInclusive ?? DateTime.fromMillisecondsSinceEpoch(0),
              max: filter.endInclusive ?? DateTime.now().add(const Duration(days: 3650)),
            )
          : null,
    );

    final albums = await PhotoManager.getAssetPathList(
      hasAll: true,
      onlyAll: true,
      type: RequestType.common,
      filterOption: option,
    );
    if (albums.isEmpty) return const [];

    final album = albums.first;
    var total = 0;
    try {
      total = await album.assetCountAsync;
    } catch (_) {
      total = 0;
    }
    onProgress?.call(LoadProgress(done: 0, total: total));
    final assets = <MediaAsset>[];
    const pageSize = 80;
    var page = 0;
    while (true) {
      final chunk = await album.getAssetListPaged(page: page, size: pageSize);
      if (chunk.isEmpty) break;
      final pageItems = <MediaAsset>[];
      for (final entity in chunk) {
        if (entity.type != AssetType.image && entity.type != AssetType.video) continue;
        final asset = _fromEntity(entity, album.name);
        if (!filter.accepts(asset)) continue;
        assets.add(asset);
        pageItems.add(asset);
      }
      if (pageItems.isNotEmpty) onBatch?.call(List<MediaAsset>.from(pageItems));
      onProgress?.call(LoadProgress(done: assets.length, total: total));
      if (chunk.length < pageSize) break;
      page++;
    }
    assets.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return assets;
  }

  MediaAsset _fromEntity(AssetEntity entity, String albumName) {
    final name = (entity.title == null || entity.title!.trim().isEmpty)
        ? entity.id
        : entity.title!.trim();
    final relative = entity.relativePath?.trim();
    final String filePath;
    if (relative != null && relative.isNotEmpty) {
      filePath = relative.endsWith('/') ? '$relative$name' : '$relative/$name';
    } else {
      filePath = name;
    }
    final kind = entity.type == AssetType.video ? MediaKind.video : MediaKind.image;
    final lat = entity.latitude;
    final lng = entity.longitude;
    GpsInfo? gps;
    if (lat != null && lng != null && !(lat == 0 && lng == 0)) {
      gps = GpsInfo(latitude: lat, longitude: lng);
    }
    final created = entity.createDateTime.millisecondsSinceEpoch <= 0
        ? entity.modifiedDateTime
        : entity.createDateTime;

    return MediaAsset(
      id: entity.id,
      filePath: filePath,
      fileName: name,
      kind: kind,
      mimeType: entity.mimeType,
      width: entity.width > 0 ? entity.width : null,
      height: entity.height > 0 ? entity.height : null,
      rotationDegrees: entity.orientation,
      duration: kind == MediaKind.video ? entity.videoDuration : null,
      createdAt: created,
      modifiedAt: entity.modifiedDateTime,
      albumName: albumName,
      gps: gps,
    );
  }

  Future<MediaAsset> ensureThumbnail(MediaAsset asset) async {
    if (asset.thumbnailBytes != null && asset.thumbnailBytes!.isNotEmpty) return asset;
    final entity = await AssetEntity.fromId(asset.id);
    if (entity == null) return asset;
    final bytes = await entity.thumbnailDataWithSize(
      const ThumbnailSize(480, 480),
      quality: 72,
    );
    if (bytes == null || bytes.isEmpty) return asset;
    return asset.copyWith(thumbnailBytes: bytes);
  }

  Future<MediaAsset> ensureDetails(MediaAsset asset) async {
    final entity = await AssetEntity.fromId(asset.id);
    if (entity == null) return asset;
    var next = asset;

    if (next.gps == null) {
      try {
        final point = await entity.latlngAsync();
        if (point != null && !(point.latitude == 0 && point.longitude == 0)) {
          next = next.copyWith(
            gps: GpsInfo(latitude: point.latitude, longitude: point.longitude),
            writeGps: true,
          );
        }
      } catch (_) {}
    }

    if (next.fileSizeBytes == null) {
      try {
        final size = await entity.fileSize;
        if (size > 0) next = next.copyWith(fileSizeBytes: size);
      } catch (_) {}
    }

    if (next.kind == MediaKind.image && next.camera.isEmpty) {
      try {
        final file = await entity.originFile;
        if (file != null && await file.exists()) {
          final length = await file.length();
          if (length > 0 && length < 40 * 1024 * 1024) {
            final headerLength = length < 2 * 1024 * 1024 ? length : 2 * 1024 * 1024;
            final raf = await file.open();
            try {
              final header = await raf.read(headerLength);
              final extension = '.${file.path.split('.').last}';
              final probed = await probeHeader(header, extension.isEmpty ? '.jpg' : extension);
              if (!probed.camera.isEmpty || probed.gps != null) {
                next = next.copyWith(
                  camera: probed.camera.isEmpty ? next.camera : probed.camera,
                  gps: probed.gps ?? next.gps,
                  width: next.width ?? probed.width,
                  height: next.height ?? probed.height,
                  filePath: file.path,
                  fileName: pBasename(file.path),
                );
              } else {
                next = next.copyWith(filePath: file.path, fileName: pBasename(file.path));
              }
            } finally {
              await raf.close();
            }
          }
        }
      } catch (_) {}
    }
    return next;
  }

  Future<String?> materializeOriginal(MediaAsset asset) async {
    final direct = asset.filePath;
    if (direct.isNotEmpty && await File(direct).exists()) return direct;
    final entity = await AssetEntity.fromId(asset.id);
    if (entity == null) return null;
    try {
      final file = await entity.originFile;
      if (file != null && await file.exists()) return file.path;
    } catch (_) {}
    return null;
  }

  /// Android opens the MediaStore item in the gallery.
  /// iOS has no public deep link to one photo, so this opens the Photos app.
  Future<void> reveal(MediaAsset asset) async {
    final entity = await AssetEntity.fromId(asset.id);
    if (Platform.isAndroid) {
      final url = await entity?.getMediaUrl();
      if (url == null || url.isEmpty) throw const LibraryException('相册里找不到这张照片');
      final mime = entity?.mimeType ?? (asset.kind == MediaKind.video ? 'video/*' : 'image/*');
      await AndroidIntent(
        action: 'action_view',
        data: url,
        type: mime,
        flags: const [1, 268435456],
      ).launch();
      return;
    }
    if (entity == null) throw const LibraryException('相册里找不到这张照片');
    final opened = await launchUrl(
      Uri.parse('photos-redirect://'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) throw const LibraryException('打不开相册');
  }
}

bool _hasAccess(PermissionState state) {
  return state == PermissionState.authorized || state == PermissionState.limited;
}

String pBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final index = normalized.lastIndexOf('/');
  if (index < 0) return path;
  return normalized.substring(index + 1);
}
