import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;

/// A compression target. [maxDimension] caps the shorter edge (aspect ratio is
/// always preserved and images are never upscaled); [quality] is 0–100.
class ImageCompressionProfile {
  const ImageCompressionProfile({
    required this.maxDimension,
    required this.quality,
  });

  final int maxDimension;
  final int quality;

  /// Listing / gallery photos. High enough to stay crisp full-screen on the
  /// guest side, while cutting a multi-MB phone JPEG to a few hundred KB.
  static const listing = ImageCompressionProfile(maxDimension: 1920, quality: 82);

  /// Avatars only ever render small, so a tight cap is fine.
  static const avatar = ImageCompressionProfile(maxDimension: 512, quality: 80);
}

/// Result of a compression attempt: the bytes to upload and their MIME type.
class CompressedImage {
  const CompressedImage({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}

/// Compresses images client-side *before* upload. On mobile it re-encodes to
/// WebP (smallest for photos); on web (where `flutter_image_compress` isn't
/// available) it resizes and re-encodes to JPEG via the pure-Dart `image`
/// package. Re-encoding also strips EXIF/GPS metadata.
///
/// Every path is best-effort: any failure, an unsupported type (PDF, GIF), or a
/// result that isn't actually smaller returns the ORIGINAL bytes unchanged, so
/// compression can never block or corrupt an upload.
class ImageCompressionService {
  ImageCompressionService._();
  static final ImageCompressionService instance = ImageCompressionService._();

  /// Only raster photos we can safely re-encode. Documents (PDF) and animated
  /// GIFs are intentionally excluded.
  static bool _isCompressible(String mime) =>
      mime == 'image/jpeg' || mime == 'image/png' || mime == 'image/webp';

  Future<CompressedImage> compress(
    Uint8List input, {
    required ImageCompressionProfile profile,
    required String sourceMime,
  }) async {
    if (!_isCompressible(sourceMime) || input.isEmpty) {
      return CompressedImage(bytes: input, mimeType: sourceMime);
    }
    try {
      final out =
          kIsWeb ? await _compressWeb(input, profile) : await _compressNative(input, profile);
      // Only keep the result if it's genuinely smaller; otherwise the original
      // was already tiny and re-encoding would just add generational loss.
      if (out != null && out.bytes.isNotEmpty && out.bytes.length < input.length) {
        return out;
      }
    } catch (e) {
      debugPrint('[ImageCompression] falling back to original: $e');
    }
    return CompressedImage(bytes: input, mimeType: sourceMime);
  }

  Future<CompressedImage?> _compressNative(
    Uint8List input,
    ImageCompressionProfile profile,
  ) async {
    final out = await FlutterImageCompress.compressWithList(
      input,
      minWidth: profile.maxDimension,
      minHeight: profile.maxDimension,
      quality: profile.quality,
      format: CompressFormat.webp,
      keepExif: false,
    );
    return CompressedImage(bytes: out, mimeType: 'image/webp');
  }

  Future<CompressedImage?> _compressWeb(
    Uint8List input,
    ImageCompressionProfile profile,
  ) async {
    final decoded = img.decodeImage(input);
    if (decoded == null) return null;

    final tooBig =
        decoded.width > profile.maxDimension || decoded.height > profile.maxDimension;
    final resized = tooBig
        ? img.copyResize(
            decoded,
            // Constrain the longer edge so neither dimension exceeds the cap.
            width: decoded.width >= decoded.height ? profile.maxDimension : null,
            height: decoded.height > decoded.width ? profile.maxDimension : null,
          )
        : decoded;

    final jpg = img.encodeJpg(resized, quality: profile.quality);
    return CompressedImage(bytes: Uint8List.fromList(jpg), mimeType: 'image/jpeg');
  }
}
