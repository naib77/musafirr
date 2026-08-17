import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../core/theme/app_colors.dart';

/// The round white control Uber and Pathao park over the corner of a map so
/// someone who has pinched and panned their way off the edge of the world can
/// get back in one tap. Every map in the app that can be moved gets one,
/// pointed at whatever that map is actually about: the host's pin on a listing,
/// the rider's own position on the directions map, the whole set of pins on the
/// search map.
///
/// Two details make this work where a bare [FloatingActionButton] doesn't:
///
///  * **Web hit-testing.** A Google map on web is a DOM element that wins the
///    browser's hit-test against anything Flutter paints above it, so a plain
///    button over the map never receives the tap. [MapFocusControls] wraps the
///    stack in a [PointerInterceptor], which puts a real DOM node behind the
///    buttons to claim the pointer. On mobile that passes its child straight
///    through, so the same tree is correct on every platform.
///  * **Reach.** 44dp minimum (48 once there's a tablet's worth of width), and
///    8dp of clear space between stacked controls, so each one is hittable with
///    a thumb rather than a fingernail.
class MapFocusButton extends StatelessWidget {
  const MapFocusButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.emphasized = false,
  });

  final IconData icon;

  /// Read out by screen readers and shown on hover / long-press. An icon-only
  /// control has no accessible name without it.
  final String label;

  final VoidCallback? onPressed;

  /// Swaps the icon for a spinner and blocks further taps. A GPS fix can take a
  /// couple of seconds, and a button that looks dead invites repeat taps.
  final bool busy;

  /// The one thing this map is about draws in brand teal; everything else in
  /// ink. At most one emphasized control per map.
  final bool emphasized;

  /// Diameter of a single control. Grows once the window is wide enough to be
  /// something other than a phone — decided on available window width, never on
  /// a hardware guess.
  static double diameterOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 600 ? 48 : 44;

  @override
  Widget build(BuildContext context) {
    final diameter = diameterOf(context);
    final color = emphasized ? AppColors.brand : AppColors.ink;
    final enabled = onPressed != null && !busy;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Tooltip(
        message: label,
        // The Semantics above already names this control; letting Tooltip add
        // its own would have a screen reader say the label twice.
        excludeFromSemantics: true,
        child: Material(
          color: AppColors.surface,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: Colors.black26,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: SizedBox(
              width: diameter,
              height: diameter,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: busy
                      ? SizedBox(
                          key: const ValueKey('busy'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                          ),
                        )
                      : Icon(
                          icon,
                          key: ValueKey<IconData>(icon),
                          size: 21,
                          color: enabled ? color : AppColors.inkMuted,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A vertical stack of [MapFocusButton]s for the corner of a map. Position it
/// with a [Positioned] inside the map's [Stack]; the primary control should be
/// last in [children] so it lands closest to the thumb.
class MapFocusControls extends StatelessWidget {
  const MapFocusControls({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    // One interceptor around the whole stack rather than one per button: the
    // gaps between them aren't interactive, and a single DOM node is cheaper.
    return PointerInterceptor(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Points [controller]'s camera at [update], animating unless the platform has
/// asked for reduced motion — a swooping camera across a whole city is exactly
/// the large-area movement that setting exists to suppress.
///
/// A null [controller] (map not created yet) is a no-op rather than a crash:
/// these calls come from taps, and a tap that lands in the frame before
/// `onMapCreated` shouldn't take the screen down.
Future<void> focusCamera(
  BuildContext context,
  GoogleMapController? controller,
  CameraUpdate update,
) async {
  if (controller == null) return;
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  if (reduceMotion) {
    await controller.moveCamera(update);
  } else {
    await controller.animateCamera(update);
  }
}

/// A camera update that frames [points]: bounds when they're meaningfully
/// spread out, a fixed street-level zoom when they're one pin (or several at
/// the same address, where a bounds fit would zoom to absurdity).
///
/// [padding] is in logical pixels around the fitted bounds. Returns null when
/// there is nothing to frame.
CameraUpdate? framePoints(List<LatLng> points, {double padding = 48}) {
  if (points.isEmpty) return null;

  var minLat = points.first.latitude;
  var maxLat = minLat;
  var minLng = points.first.longitude;
  var maxLng = minLng;
  for (final p in points) {
    minLat = p.latitude < minLat ? p.latitude : minLat;
    maxLat = p.latitude > maxLat ? p.latitude : maxLat;
    minLng = p.longitude < minLng ? p.longitude : minLng;
    maxLng = p.longitude > maxLng ? p.longitude : maxLng;
  }

  if (maxLat - minLat < 0.002 && maxLng - minLng < 0.002) {
    return CameraUpdate.newLatLngZoom(LatLng(minLat, minLng), 15);
  }

  return CameraUpdate.newLatLngBounds(
    LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    ),
    padding,
  );
}
