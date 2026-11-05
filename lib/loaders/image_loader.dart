import '../models/media_asset.dart';
import '../models/media_filter.dart';

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
  Future<List<MediaAsset>> load({MediaFilter filter = const MediaFilter()});

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
