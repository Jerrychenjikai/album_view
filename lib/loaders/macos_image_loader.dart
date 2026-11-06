import 'dart:io';

import 'package:macos_secure_bookmarks/macos_secure_bookmarks.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/media_asset.dart';
import '../models/media_filter.dart';
import 'desktop_library.dart';
import 'image_loader.dart';

/// macOS loader. Swap the import in `lib/main.dart` with one of:
///
/// * `windows_image_loader.dart`
/// * `ios_image_loader.dart`
/// * `android_image_loader.dart`
///
/// App Sandbox does not allow a silent walk of Pictures, the folder beside
/// the `.app`, or the rest of the disk. The user picks a folder in the system
/// panel (see `AlbumHomePage`). That grant is stored as a security-scoped
/// bookmark under [bookmarkPrefsKey] and started again on the next launch.
/// The scope stays open for the whole process so the scan and later
/// thumbnails keep working. There is no default folder.
class PlatformImageLoader implements ImageLoader {
  const PlatformImageLoader();

  static final DesktopLibrary _library = DesktopLibrary(defaultRoot: _noDefaultFolder);

  static final SecureBookmarks _bookmarks = SecureBookmarks();

  static const String bookmarkPrefsKey = 'macos_folder_bookmark';

  static Directory? _scoped;
  static bool _started = false;
  static Future<void>? _pending;
  static LibraryException? _lastAccessError;

  @override
  bool get canConfigureFolder => true;

  @override
  Future<void> setImagePath(String path) async {
    final trimmed = path.trim();
    final prefs = await SharedPreferences.getInstance();
    if (trimmed.isEmpty) {
      await _releaseScope();
      await prefs.remove(bookmarkPrefsKey);
      await _library.setImagePath('');
      _lastAccessError = null;
      return;
    }
    final directory = Directory(trimmed);
    try {
      final bookmark = await _bookmarks.bookmark(directory);
      if (bookmark.trim().isEmpty) {
        throw const LibraryException('没有拿到可以保存的授权。');
      }
      await prefs.setString(bookmarkPrefsKey, bookmark);
    } catch (_) {
      // The panel grant still covers this launch. Without a bookmark the
      // next launch has to ask again.
      await prefs.remove(bookmarkPrefsKey);
    }
    await _hold(directory, requireStart: false);
    await _library.setImagePath(directory.absolute.path);
    _lastAccessError = null;
  }

  @override
  Future<String?> storedImagePath() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmark = prefs.getString(bookmarkPrefsKey)?.trim();
    if (bookmark == null || bookmark.isEmpty) return null;
    final stored = await _library.storedImagePath();
    if (stored != null && stored.isNotEmpty) return stored;
    // Bookmark exists but the path string does not. Non-null so startup
    // restores the bookmark instead of opening the panel again.
    return bookmark;
  }

  @override
  Future<String> describeSource() async {
    try {
      await _ensureAccess();
    } catch (_) {}
    if (_scoped == null) return '';
    final stored = await _library.storedImagePath();
    if (stored == null || stored.isEmpty) return '';
    return stored;
  }

  @override
  Future<List<MediaAsset>> load({
    MediaFilter filter = const MediaFilter(),
    void Function(List<MediaAsset> batch)? onBatch,
    void Function(LoadProgress progress)? onProgress,
  }) async {
    try {
      await _ensureAccess();
    } catch (error) {
      _lastAccessError = null;
      if (error is LibraryException) rethrow;
      throw const LibraryException('上次选的文件夹已经失效。请点「来源」再选一次。');
    }
    if (_scoped == null) {
      final failure = _lastAccessError;
      _lastAccessError = null;
      throw failure ?? const LibraryException('请点「来源」，在弹窗里选一个照片文件夹。');
    }
    _lastAccessError = null;
    return _library.load(filter: filter, onBatch: onBatch, onProgress: onProgress);
  }

  @override
  Future<MediaAsset> ensureThumbnail(MediaAsset asset) async {
    await _ensureAccess();
    return _library.ensureThumbnail(asset);
  }

  @override
  Future<MediaAsset> ensureDetails(MediaAsset asset) async {
    await _ensureAccess();
    return _library.ensureDetails(asset);
  }

  @override
  Future<String?> materializeOriginal(MediaAsset asset) async {
    await _ensureAccess();
    return _library.materializeOriginal(asset);
  }

  @override
  Future<void> reveal(MediaAsset asset) async {
    await _ensureAccess();
    await _library.reveal(asset);
  }

  static Future<void> _ensureAccess() {
    if (_scoped != null) return Future<void>.value();
    return _pending ??= _restore().whenComplete(() => _pending = null);
  }

  static Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final bookmark = prefs.getString(bookmarkPrefsKey)?.trim();
    if (bookmark == null || bookmark.isEmpty) {
      await _library.setImagePath('');
      return;
    }
    try {
      final resolved = await _bookmarks.resolveBookmark(bookmark, isDirectory: true);
      final directory = resolved is Directory ? resolved : Directory(resolved.path);
      await _hold(directory, requireStart: true);
      await _library.setImagePath(directory.path);
      _lastAccessError = null;
    } catch (error) {
      await prefs.remove(bookmarkPrefsKey);
      await _library.setImagePath('');
      await _releaseScope();
      final failure = error is LibraryException
          ? error
          : const LibraryException('上次选的文件夹已经失效。请点「来源」再选一次。');
      _lastAccessError = failure;
      throw failure;
    }
  }

  static Future<void> _hold(Directory directory, {required bool requireStart}) async {
    await _releaseScope();
    final started = await _bookmarks.startAccessingSecurityScopedResource(directory);
    if (requireStart && !started) {
      throw const LibraryException('系统没有继续允许读取上次选的文件夹。请点「来源」再选一次。');
    }
    _scoped = directory;
    _started = started;
  }

  static Future<void> _releaseScope() async {
    final previous = _scoped;
    final started = _started;
    _scoped = null;
    _started = false;
    if (!started || previous == null) return;
    try {
      await _bookmarks.stopAccessingSecurityScopedResource(previous);
    } catch (_) {}
  }
}

/// Never a silent default. Scanning this means the bookmark was skipped.
Directory _noDefaultFolder() {
  throw const LibraryException('请点「来源」，在弹窗里选一个照片文件夹。');
}
