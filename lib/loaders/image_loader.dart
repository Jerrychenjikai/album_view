import '../models/media_asset.dart';
import '../models/media_filter.dart';

/// How far a folder or album scan has got.
///
/// [total] is 0 while the size is still unknown. [counting] means the loader
/// is only listing files and has not started reading them yet.
class LoadProgress {
  final int done;
  final int total;
  final bool counting;

  const LoadProgress({required this.done, required this.total, this.counting = false});

  double? get fraction {
    if (counting || total <= 0) return null;
    final value = done / total;
    if (value.isNaN) return null;
    return value.clamp(0.0, 1.0);
  }
}

/// The contract implemented by every `{platform}_image_loader.dart`.
///
/// Switch platforms by replacing the import in `lib/main.dart`. The class
/// name stays [PlatformImageLoader], so call sites do not change.
abstract interface class ImageLoader {
  bool get canConfigureFolder;

  /// Desktop: writes shared_preferences key `image_path`.
  /// Empty string clears the key so the loader falls back to the app folder.
  /// Mobile: no-op. The system photo library is the only source.
  Future<void> setImagePath(String path);

  /// The stored `image_path`, or null when the key is absent.
  Future<String?> storedImagePath();

  /// Short label of the folder or album currently being read.
  Future<String> describeSource();

  /// Returns every image and video that matches [filter].
  /// Thumbnails may still be empty; call [ensureThumbnail] for those.
  /// [onBatch] is invoked as items are discovered so the timeline can fill
  /// in pieces instead of waiting for the whole library.
  /// [onProgress] reports the scan so the toolbar can show when batches
  /// will become openable.
  Future<List<MediaAsset>> load({
    MediaFilter filter = const MediaFilter(),
    void Function(List<MediaAsset> batch)? onBatch,
    void Function(LoadProgress progress)? onProgress,
  });

  Future<MediaAsset> ensureThumbnail(MediaAsset asset);

  /// Fills GPS, camera and file size when the fast listing omitted them.
  Future<MediaAsset> ensureDetails(MediaAsset asset);

  /// Absolute path of the original file, exporting it from the system library
  /// when the listing only had an id. Null when it cannot be read.
  Future<String?> materializeOriginal(MediaAsset asset);

  /// Desktop: select the file in Finder or Explorer.
  /// Phone: open this item in the system gallery.
  Future<void> reveal(MediaAsset asset);
}

class LibraryException implements Exception {
  final String message;
  const LibraryException(this.message);

  @override
  String toString() => message;
}

/// Shared preferences key. Do not rename — desktop loaders read this exact key.
const String imagePathPrefsKey = 'image_path';
