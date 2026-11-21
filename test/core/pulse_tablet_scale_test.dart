import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/core/widgets/pulse/pulse_tablet_scale.dart';

void main() {
  double f(double w, double h, [TargetPlatform p = TargetPlatform.iOS]) =>
      PulseTabletScale.factorFor(Size(w, h), platform: p);

  test('13-inch iPads lay out with an 800 dp short side', () {
    expect(f(1024, 1366), closeTo(1.28, 0.001));
    expect(f(1366, 1024), closeTo(1.28, 0.001));
    expect(f(1032, 1376), closeTo(1.29, 0.001));
  });

  test('phones, iPad mini and 11-inch iPads are not scaled', () {
    expect(f(402, 874), 1);
    expect(f(744, 1133), 1);
    expect(f(834, 1194), 1);
  });

  test('only on iOS', () {
    expect(f(1100, 1440, TargetPlatform.macOS), 1);
    expect(f(1024, 1366, TargetPlatform.android), 1);
  });
}
