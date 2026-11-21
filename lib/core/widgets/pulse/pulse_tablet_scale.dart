import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// Lays large iPads out like Pulse's design tablet and draws the result bigger.
///
/// The tablet layouts were designed on an 8" Android tablet (800 dp short
/// side). A 12.9"/13" iPad has a 1024 pt short side, so the same layout came out
/// small on a huge canvas: two stretched columns, oversized cards and empty
/// space. Here every window whose short side is clearly larger than the design
/// tablet gets the layout of an 800 dp-short-side window, scaled up to fill it.
/// Phones and 11" iPads (834 pt) are untouched (factor ≤ 1.05). iOS only: desktop
/// windows and Android keep their own layouts.
///
/// The device pixel ratio is raised by the same factor so text and images are
/// rasterised at full resolution, and [FittedBox] keeps hit testing correct.
class PulseTabletScale extends StatelessWidget {
  const PulseTabletScale({super.key, required this.child});

  final Widget child;

  /// The design tablet's short side.
  static const designShortSide = 800.0;

  /// Below this the window is used as is.
  static const threshold = 1.05;

  static double factorFor(Size size, {TargetPlatform? platform}) {
    if ((platform ?? defaultTargetPlatform) != TargetPlatform.iOS) return 1;
    final f = size.shortestSide / designShortSide;
    return f > threshold ? f : 1;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final f = factorFor(mq.size);
    if (f == 1) return child;
    final size = mq.size / f;
    return MediaQuery(
      data: mq.copyWith(
        size: size,
        devicePixelRatio: mq.devicePixelRatio * f,
        padding: mq.padding / f,
        viewPadding: mq.viewPadding / f,
        viewInsets: mq.viewInsets / f,
        systemGestureInsets: mq.systemGestureInsets / f,
      ),
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    );
  }
}
