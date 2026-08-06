import 'package:flutter/widgets.dart';

/// Layout breakpoints. Everything below [wide] renders the phone/tablet layout
/// exactly as before; at or above it we switch to the desktop framing (left
/// navigation rail + centered, max-width content). This keeps the mobile design
/// — which is already good — completely untouched.
class Responsive {
  Responsive._();

  /// Width at/above which the desktop layout kicks in. Chosen so large tablets
  /// in landscape and real desktops get the rail, while phones and portrait
  /// tablets keep the bottom navigation bar.
  static const double wide = 1000;

  /// Max width the primary content is allowed to stretch to on desktop. Kept
  /// deliberately narrower than the viewport so the content sits as a centered
  /// panel with clear breathing room on both sides, rather than spanning the
  /// whole monitor.
  static const double contentMaxWidth = 1040;

  /// Comfortable width for single-column forms (login/OTP/profile). Narrow
  /// enough to read as a centered card on desktop; wider than any phone, so it
  /// is a no-op on mobile (the content simply fills the screen as before).
  static const double formMaxWidth = 440;

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wide;
}

/// Centers [child] and caps its width at [maxWidth]. On screens narrower than
/// [maxWidth] (i.e. phones) it changes nothing — the child just fills the width
/// as it did before — so it is safe to apply unconditionally.
class ResponsiveCenter extends StatelessWidget {
  const ResponsiveCenter({
    super.key,
    required this.child,
    this.maxWidth = Responsive.contentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // topCenter (not Center) so vertical alignment is unchanged from a plain
    // top-anchored scroll body — only the horizontal width is capped. Must wrap
    // the scroll view from the OUTSIDE (bounded height); placing a Center/Align
    // inside a vertical SingleChildScrollView would hit unbounded height.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
