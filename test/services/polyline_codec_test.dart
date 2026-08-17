import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/polyline_codec.dart';

/// Run this on BOTH platforms — the bug it guards against only ever appeared on
/// one of them:
///
///   flutter test test/services/polyline_codec_test.dart
///   flutter test --platform chrome test/services/polyline_codec_test.dart
void main() {
  // Every point here has a negative longitude delta, which is the path that
  // goes through the one's-complement branch — the branch that dart2js got
  // wrong when it was written with `~`.
  test('decodes Google\'s reference polyline', () {
    final points = decodePolyline(r'_p~iF~ps|U_ulLnnqC_mqNvxq`@');

    expect(points, hasLength(3));
    expect(points[0].latitude, closeTo(38.5, 1e-9));
    expect(points[0].longitude, closeTo(-120.2, 1e-9));
    expect(points[1].latitude, closeTo(40.7, 1e-9));
    expect(points[1].longitude, closeTo(-120.95, 1e-9));
    expect(points[2].latitude, closeTo(43.252, 1e-9));
    expect(points[2].longitude, closeTo(-126.453, 1e-9));
  });

  test('keeps a Dhaka route in Dhaka', () {
    // The shape of the bug report: distance and duration were right, but the
    // drawn line ran off the map. Any decoder that mishandles the complement
    // branch lands thousands of degrees away, so a locality assertion catches
    // it far more clearly than an exact-value one.
    final points = decodePolyline(r'kmipCcuyfPk\{m@od@wcA');

    expect(points, hasLength(3));
    for (final p in points) {
      expect(p.latitude, closeTo(23.81, 0.05));
      expect(p.longitude, closeTo(90.42, 0.05));
    }
  });

  test('handles negative deltas in both axes', () {
    // The same route walked backwards: every delta flips sign, so both axes go
    // through the complement branch on every point.
    final back = decodePolyline(r'gpkpCwh}fPnd@vcAj\zm@');

    expect(back.first.latitude, closeTo(23.821, 1e-9));
    expect(back.first.longitude, closeTo(90.431, 1e-9));
    expect(back.last.latitude, closeTo(23.8103, 1e-9));
    expect(back.last.longitude, closeTo(90.4125, 1e-9));

    // Strictly decreasing in both axes — the property that breaks first when
    // negative deltas decode as huge positive numbers.
    for (var i = 1; i < back.length; i++) {
      expect(back[i].latitude, lessThan(back[i - 1].latitude));
      expect(back[i].longitude, lessThan(back[i - 1].longitude));
    }
  });
}
