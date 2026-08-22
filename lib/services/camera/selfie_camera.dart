import 'package:camera/camera.dart';

/// Picks the camera a selfie should be taken with.
///
/// Exists because `image_picker`'s `preferredCameraDevice: CameraDevice.front`
/// is only a HINT. On Android it is delivered to whichever camera app handles
/// the intent as the extras `android.intent.extras.CAMERA_FACING` and
/// `android.intent.extra.USE_FRONT_CAMERA`, and that app is free to ignore
/// both — many OEM camera apps do, which is why identity verification kept
/// opening the rear camera. Mobile browsers that hand `capture="user"` off to
/// the same camera app inherit the problem.
///
/// The only way to be sure is to stop asking and choose the lens ourselves.
///
/// Returns null when the device reports no front-facing camera, which is a real
/// case (some tablets, desktop web with only an external cam). Callers must
/// fall back rather than assume.
CameraDescription? selectSelfieCamera(List<CameraDescription> cameras) {
  // Only an explicitly front-facing lens will do. `external` is deliberately
  // excluded: a clip-on webcam usually faces the user, but the platform does
  // not say so, and guessing would put an unmirrored, wrongly-oriented feed on
  // screen. Never fall back to `cameras.first` — on nearly every Android device
  // that is the rear camera, which is the bug this function exists to prevent.
  for (final camera in cameras) {
    if (camera.lensDirection == CameraLensDirection.front) return camera;
  }
  return null;
}
