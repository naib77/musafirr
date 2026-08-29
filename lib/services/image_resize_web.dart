import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Resizes and re-encodes an image using the browser's own codecs.
///
/// Why this exists: the pure-Dart `image` package decode → resize → encode
/// chain runs on the Dart main thread, and Flutter web has no isolates, so
/// `compute()` would not move it off. A multi-megapixel phone photo therefore
/// froze the tab for seconds — once per photo, so a ten-image gallery upload
/// froze it ten times. The browser does the same work in native code, and
/// `createImageBitmap` decodes off the main thread entirely.
///
/// Returns null on any failure (no OffscreenCanvas, a codec the browser will
/// not encode, a decode error). The caller falls back to the Dart path, so a
/// browser without these APIs still compresses — just slowly, as before.
Future<Uint8List?> resizeWithBrowserCodecs(
  Uint8List input, {
  required int maxDimension,
  required int quality,
}) async {
  web.ImageBitmap? bitmap;
  try {
    final blob = web.Blob(
      [input.toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );

    // Decoding happens off the main thread; this is the expensive step and the
    // whole reason for going through the browser.
    bitmap = await web.window.createImageBitmap(blob).toDart;

    final width = bitmap.width;
    final height = bitmap.height;
    if (width == 0 || height == 0) return null;

    // Never upscale, and constrain the longer edge so neither dimension
    // exceeds the cap — same rule the Dart path applies.
    final longest = width > height ? width : height;
    final scale = longest > maxDimension ? maxDimension / longest : 1.0;
    final targetW = (width * scale).round().clamp(1, width);
    final targetH = (height * scale).round().clamp(1, height);

    final canvas = web.OffscreenCanvas(targetW, targetH);
    final ctx =
        canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D?;
    if (ctx == null) return null;
    ctx.drawImage(bitmap, 0, 0, targetW.toDouble(), targetH.toDouble());

    final encoded = await canvas
        .convertToBlob(
          web.ImageEncodeOptions(
            type: 'image/jpeg',
            // The DOM API takes 0..1; the app's profiles are 0..100.
            quality: quality / 100,
          ),
        )
        .toDart;

    final buffer = await encoded.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  } catch (_) {
    return null;
  } finally {
    // Bitmaps hold decoded pixel buffers; leaving them for the GC is how a
    // gallery upload turns into a memory spike.
    bitmap?.close();
  }
}
