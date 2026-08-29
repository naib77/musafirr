import 'package:flutter/foundation.dart';

/// Non-web placeholder. Mobile compresses through `flutter_image_compress`,
/// which is native code on a platform thread already, so nothing here is ever
/// reached — the conditional import just has to resolve.
Future<Uint8List?> resizeWithBrowserCodecs(
  Uint8List input, {
  required int maxDimension,
  required int quality,
}) async =>
    null;
