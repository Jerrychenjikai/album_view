import 'dart:io';

import '../models/media_asset.dart';
import '../models/media_filter.dart';
import 'desktop_library.dart';
import 'image_loader.dart';

/// Windows loader. Swap the import in `lib/main.dart` with one of:
///
/// * `macos_image_loader.dart`
/// * `ios_image_loader.dart`
/// * `android_image_loader.dart`
///
/// All four files expose a class named [PlatformImageLoader] with the same
/// methods ([ImageLoader]).
///
/// Reads every image and video under the folder stored in shared_preferences
/// key `image_path`, including the folder itself and nested subfolders.
/// When the key is missing, the default is the directory that contains the
/// `.exe`.
class PlatformImageLoader implements ImageLoader {
  const PlatformImageLoader();

  static final DesktopLibrary _library = DesktopLibrary(defaultRoot: _defaultAppDirectory);

  @override
  bool get canConfigureFolder => true;

  @override
  Future<void> setImagePath(String path) => _library.setImagePath(path);

  @override
  Future<String?> storedImagePath() => _library.storedImagePath();

  @override
  Future<String> describeSource() => _library.describeSource();

  @override
  Future<List<MediaAsset>> load({MediaFilter filter = const MediaFilter()}) {
    return _library.load(filter: filter);
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

Directory _defaultAppDirectory() => File(Platform.resolvedExecutable).parent;
