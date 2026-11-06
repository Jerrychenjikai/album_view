import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'jpeg_thumb.dart';

/// Explorer's thumbnail for a video (or any file the image decoder rejected).
///
/// Runs in its own isolate. Shell extraction can take a moment the first time
/// and must not sit on the UI thread. Later opens read the JPEG we cache.
Future<Uint8List?> windowsFileThumbnail(String path) {
  if (!Platform.isWindows) return Future<Uint8List?>.value(null);
  return Isolate.run(() => _shellThumbnail(path));
}

const int _coinitApartment = 0x2;
const int _siigbfThumbnailOnly = 0x8;
const int _siigbfBiggerSizeOk = 0x1;
const int _biRgb = 0;
const int _dibRgbColors = 0;

final class _GUID extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

final class _SIZE extends Struct {
  @Int32()
  external int cx;
  @Int32()
  external int cy;
}

final class _BITMAP extends Struct {
  @Int32()
  external int bmType;
  @Int32()
  external int bmWidth;
  @Int32()
  external int bmHeight;
  @Int32()
  external int bmWidthBytes;
  @Uint16()
  external int bmPlanes;
  @Uint16()
  external int bmBitsPixel;
  external Pointer<Void> bmBits;
}

final class _BITMAPINFOHEADER extends Struct {
  @Uint32()
  external int biSize;
  @Int32()
  external int biWidth;
  @Int32()
  external int biHeight;
  @Uint16()
  external int biPlanes;
  @Uint16()
  external int biBitCount;
  @Uint32()
  external int biCompression;
  @Uint32()
  external int biSizeImage;
  @Int32()
  external int biXPelsPerMeter;
  @Int32()
  external int biYPelsPerMeter;
  @Uint32()
  external int biClrUsed;
  @Uint32()
  external int biClrImportant;
}

typedef _CoInitC = Int32 Function(Pointer<Void> reserved, Uint32 mode);
typedef _CoInitD = int Function(Pointer<Void> reserved, int mode);
typedef _CoUninitC = Void Function();
typedef _CoUninitD = void Function();
typedef _ShCreateC = Int32 Function(
  Pointer<Utf16> path,
  Pointer<Void> bind,
  Pointer<_GUID> iid,
  Pointer<Pointer<Void>> out,
);
typedef _ShCreateD = int Function(
  Pointer<Utf16> path,
  Pointer<Void> bind,
  Pointer<_GUID> iid,
  Pointer<Pointer<Void>> out,
);
typedef _GetImageC = Int32 Function(Pointer<Void> self, _SIZE size, Uint32 flags, Pointer<IntPtr> bitmap);
typedef _GetImageD = int Function(Pointer<Void> self, _SIZE size, int flags, Pointer<IntPtr> bitmap);
typedef _ReleaseC = Uint32 Function(Pointer<Void> self);
typedef _ReleaseD = int Function(Pointer<Void> self);
typedef _GetObjectC = Int32 Function(IntPtr object, Int32 size, Pointer<_BITMAP> out);
typedef _GetObjectD = int Function(int object, int size, Pointer<_BITMAP> out);
typedef _GetDC_C = IntPtr Function(IntPtr window);
typedef _GetDC_D = int Function(int window);
typedef _ReleaseDC_C = Int32 Function(IntPtr window, IntPtr dc);
typedef _ReleaseDC_D = int Function(int window, int dc);
typedef _GetDIBitsC = Int32 Function(
  IntPtr dc,
  IntPtr bitmap,
  Uint32 start,
  Uint32 lines,
  Pointer<Uint8> bits,
  Pointer<_BITMAPINFOHEADER> info,
  Uint32 usage,
);
typedef _GetDIBitsD = int Function(
  int dc,
  int bitmap,
  int start,
  int lines,
  Pointer<Uint8> bits,
  Pointer<_BITMAPINFOHEADER> info,
  int usage,
);
typedef _DeleteObjectC = Int32 Function(IntPtr object);
typedef _DeleteObjectD = int Function(int object);

Uint8List? _shellThumbnail(String path) {
  DynamicLibrary ole32;
  DynamicLibrary shell32;
  DynamicLibrary gdi32;
  DynamicLibrary user32;
  try {
    ole32 = DynamicLibrary.open('ole32.dll');
    shell32 = DynamicLibrary.open('shell32.dll');
    gdi32 = DynamicLibrary.open('gdi32.dll');
    user32 = DynamicLibrary.open('user32.dll');
  } catch (_) {
    return null;
  }

  final coInit = ole32.lookupFunction<_CoInitC, _CoInitD>('CoInitializeEx');
  final coUninit = ole32.lookupFunction<_CoUninitC, _CoUninitD>('CoUninitialize');
  final shCreate = shell32.lookupFunction<_ShCreateC, _ShCreateD>('SHCreateItemFromParsingName');
  final getObject = gdi32.lookupFunction<_GetObjectC, _GetObjectD>('GetObjectW');
  final getDC = user32.lookupFunction<_GetDC_C, _GetDC_D>('GetDC');
  final releaseDC = user32.lookupFunction<_ReleaseDC_C, _ReleaseDC_D>('ReleaseDC');
  final getDIBits = gdi32.lookupFunction<_GetDIBitsC, _GetDIBitsD>('GetDIBits');
  final deleteObject = gdi32.lookupFunction<_DeleteObjectC, _DeleteObjectD>('DeleteObject');

  final co = coInit(nullptr, _coinitApartment);
  final undoCom = co == 0;
  final iid = calloc<_GUID>();
  final pathPtr = path.toNativeUtf16();
  final out = calloc<Pointer<Void>>();
  Pointer<Void> item = nullptr;
  var bitmap = 0;
  try {
    iid.ref
      ..data1 = 0xBCC18B79
      ..data2 = 0xBA16
      ..data3 = 0x442F;
    const tail = <int>[0x80, 0xC4, 0x8A, 0x59, 0xC3, 0x0C, 0x46, 0x3B];
    for (var i = 0; i < tail.length; i++) {
      iid.ref.data4[i] = tail[i];
    }
    final created = shCreate(pathPtr, nullptr, iid, out);
    if (created < 0 || out.value == nullptr) return null;
    item = out.value;

    // item points at the vtable pointer. Slot 0 is QueryInterface, not the
    // table base, so fromAddress needs elementAt(slot).value — GetImage is 3.
    final vtable = item.cast<Pointer<IntPtr>>().value;
    final getImage = Pointer<NativeFunction<_GetImageC>>.fromAddress(
      vtable.elementAt(3).value,
    ).asFunction<_GetImageD>();
    final size = calloc<_SIZE>();
    final bitmapOut = calloc<IntPtr>();
    try {
      size.ref
        ..cx = 480
        ..cy = 480;
      final hr = getImage(item, size.ref, _siigbfThumbnailOnly | _siigbfBiggerSizeOk, bitmapOut);
      if (hr < 0 || bitmapOut.value == 0) return null;
      bitmap = bitmapOut.value;
    } finally {
      calloc.free(size);
      calloc.free(bitmapOut);
    }

    final info = calloc<_BITMAP>();
    try {
      final got = getObject(bitmap, sizeOf<_BITMAP>(), info);
      if (got == 0) return null;
      final width = info.ref.bmWidth;
      final height = info.ref.bmHeight.abs();
      if (width <= 0 || height <= 0 || width > 4096 || height > 4096) return null;
      final header = calloc<_BITMAPINFOHEADER>();
      final pixels = calloc<Uint8>(width * height * 4);
      final dc = getDC(0);
      try {
        header.ref
          ..biSize = sizeOf<_BITMAPINFOHEADER>()
          ..biWidth = width
          ..biHeight = height
          ..biPlanes = 1
          ..biBitCount = 32
          ..biCompression = _biRgb;
        final rows = getDIBits(dc, bitmap, 0, height, pixels, header, _dibRgbColors);
        if (rows == 0) return null;
        final tight = Uint8List(width * height * 4);
        final view = pixels.asTypedList(tight.length);
        final stride = width * 4;
        for (var y = 0; y < height; y++) {
          final src = (height - 1 - y) * stride;
          tight.setRange(y * stride, (y + 1) * stride, view, src);
        }
        return jpegFromPixels(tight, width, height, bgra: true);
      } finally {
        if (dc != 0) releaseDC(0, dc);
        calloc.free(header);
        calloc.free(pixels);
      }
    } finally {
      calloc.free(info);
    }
  } catch (_) {
    return null;
  } finally {
    if (bitmap != 0) deleteObject(bitmap);
    if (item != nullptr) {
      final vtable = item.cast<Pointer<IntPtr>>().value;
      final release = Pointer<NativeFunction<_ReleaseC>>.fromAddress(
        vtable.elementAt(2).value,
      ).asFunction<_ReleaseD>();
      release(item);
    }
    calloc.free(out);
    calloc.free(pathPtr);
    calloc.free(iid);
    if (undoCom) coUninit();
  }
}
