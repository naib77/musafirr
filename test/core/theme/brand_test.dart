import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/core/theme/brand.dart';

/// White sits on both ends of the search button's gradient, so both ends are
/// held to WCAG AA for text — the same bar every palette token that carries
/// text is held to.
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  test('white on brand rose clears 4.5:1 at both gradient ends', () {
    expect(contrast(Colors.white, Brand.rose), greaterThanOrEqualTo(4.5));
    expect(contrast(Colors.white, Brand.roseDeep), greaterThanOrEqualTo(4.5));
  });

  test('roseDeep is the darker end, and still recognisably the brand', () {
    expect(Brand.roseDeep.computeLuminance(),
        lessThan(Brand.rose.computeLuminance()));
    final a = HSLColor.fromColor(Brand.rose),
        b = HSLColor.fromColor(Brand.roseDeep);
    expect((a.hue - b.hue).abs(), lessThan(6));
  });
}
