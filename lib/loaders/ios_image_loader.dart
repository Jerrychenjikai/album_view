import '../models/media_asset.dart';
import '../models/media_filter.dart';
import 'image_loader.dart';
import 'mobile_library.dart';

/// iOS loader. Swap the import in `lib/main.dart` with one of:
///
/// * `macos_image_loader.dart`
/// * `windows_image_loader.dart`
/// * `android_image_loader.dart`
///
/// All four files expose a class named [PlatformImageLoader] with the same
/// methods ([ImageLoader]).
///
/// Reads every photo and video in the system library (the Recents / All album).
/// `image_path` is not used. Add the plist fragment in `platform_config/`.
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
  Future<List<MediaAsset>> load({MediaFilter filter = const MediaFilter()}) {
    return _library.load(filter: filter);
  }

  @override
  Future<MediaAsset> ensureThumbnail(MediaAsset asset) => _library.ensureThumbnail(asset);

  @override
  Future<MediaAsset> ensureDetails(MediaAsset asset) => _library.ensureDetails(asset);
}
