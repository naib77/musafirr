import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/camera/selfie_camera.dart';

/// Which lens a selfie is taken with.
///
/// This is the whole bug: identity verification opened the REAR camera, because
/// `preferredCameraDevice: CameraDevice.front` is a hint the phone's camera app
/// may ignore — and most Android devices list the rear camera first, so any
/// "just take the first one" selection reproduces the fault exactly.
void main() {
  CameraDescription cam(String name, CameraLensDirection dir) {
    return CameraDescription(
      name: name,
      lensDirection: dir,
      sensorOrientation: 90,
    );
  }

  final back = cam('0', CameraLensDirection.back);
  final front = cam('1', CameraLensDirection.front);
  final external = cam('2', CameraLensDirection.external);

  group('choosing the selfie lens', () {
    test('picks the front camera even when the rear is listed first', () {
      // The real Android ordering, and the exact shape of the reported bug.
      expect(selectSelfieCamera([back, front]), front);
    });

    test('picks the front camera when it is listed first', () {
      expect(selectSelfieCamera([front, back]), front);
    });

    test('picks the front camera past several rear lenses', () {
      // Modern phones report wide / ultra-wide / tele as separate back cameras.
      final wide = cam('3', CameraLensDirection.back);
      final tele = cam('4', CameraLensDirection.back);
      expect(selectSelfieCamera([back, wide, tele, front]), front);
    });

    test('never returns a rear camera', () {
      for (final list in [
        [back],
        [back, external],
        [external, back],
      ]) {
        final chosen = selectSelfieCamera(list);
        expect(
          chosen?.lensDirection,
          isNot(CameraLensDirection.back),
          reason: 'a selfie must never be taken with the rear lens — '
              'returning null so the caller can fall back is correct',
        );
      }
    });

    test('an external camera is not treated as front-facing', () {
      // A clip-on webcam faces the user in practice, but the platform does not
      // say so, and guessing would put an unmirrored, wrongly-oriented feed on
      // screen. Fall back instead.
      expect(selectSelfieCamera([external]), isNull);
    });

    test('no front camera yields null so the caller can fall back', () {
      expect(selectSelfieCamera([back]), isNull);
      expect(selectSelfieCamera([]), isNull);
    });
  });
}
