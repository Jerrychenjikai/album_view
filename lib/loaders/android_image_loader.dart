import '../models/media_asset.dart';
import '../models/media_filter.dart';
import 'image_loader.dart';
import 'mobile_library.dart';

/// Android loader. Swap the import in `lib/main.dart` with one of:
///
/// * `macos_image_loader.dart`
/// * `windows_image_loader.dart`
/// * `ios_image_loader.dart`
///
/// All four files expose a class named [PlatformImageLoader] with the same
/// methods ([ImageLoader]).
///
/// Reads every photo and video in the system library (the All album).
/// `image_path` is not used. Add the manifest fragment in `platform_config/`.
/// On Android 10+ GPS is filled later by [ensureDetails], because MediaStore
/// does not return location on the initial listing.
class PlatformImageLoader implements ImageLoader {
  const PlatformImageLoader();

  static const MobileLibrary _library = MobileLibrary();

  @override
  bool get canConfigureFolder => false;

  @override
  Future<void> setImagePath(String path) async {}

  @override
  Future<String?> storedImagePath() async => null;

  @override
  Future<String> describeSource() async => '系统相册';

  @override
  Future<List<MediaAsset>> load({
    MediaFilter filter = const MediaFilter(),
    bool refresh = false,
    void Function(List<MediaAsset> batch)? onBatch,
    void Function(LoadProgress progress)? onProgress,
  }) {
    return _library.load(filter: filter, refresh: refresh, onBatch: onBatch, onProgress: onProgress);
  }

  @override
  Future<MediaAsset> ensureThumbnail(MediaAsset asset) => _library.ensureThumbnail(asset);

  @override
  Future<MediaAsset> ensureDetails(MediaAsset asset) => _library.ensureDetails(asset);

  @override
  Future<String?> materializeOriginal(MediaAsset asset) => _library.materializeOriginal(asset);

  @override
  Future<void> reveal(MediaAsset asset) => _library.reveal(asset);
}
