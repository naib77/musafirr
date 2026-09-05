import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// Which edge of a panel lines up with its segment.
///
/// The rightmost segments anchor by their right edge so a wide panel opens
/// inwards instead of off the side of the window. There is no automatic flip:
/// the bar's geometry is fixed and known, so choosing per segment is both
/// simpler and more predictable than measuring at open time.
enum SearchPopoverAlign { left, center, right }

/// The floating panel behind one search segment.
///
/// ## Why an overlay rather than a route
///
/// The existing search is a full-screen `showModalBottomSheet` — a route. A
/// route cannot be anchored under the control that opened it, and pushing one
/// per segment would put a page transition between "tap Where" and "type a
/// place". These panels are chrome attached to a bar that is itself chrome, so
/// they live in the [Overlay], positioned against their own segment through a
/// [LayerLink].
///
/// ## The scrim starts below the header, deliberately
///
/// Airbnb dims the page behind an open panel but leaves the bar itself bright,
/// so you can see which segment is active and click straight to another one. A
/// full-screen scrim would grey the header too and make the whole bar read as
/// disabled. So [scrimTop] is the header's bottom in global coordinates, and
/// the dim starts there.
///
/// The scrim is also what dismisses the panel. It is a real hit-testing
/// surface rather than a `TapRegion`, which additionally stops a click landing
/// on a listing card the guest could not actually see properly.
class SearchPopover extends StatelessWidget {
  const SearchPopover({
    super.key,
    required this.link,
    required this.align,
    required this.scrimTop,
    required this.onDismiss,
    required this.width,
    required this.child,
  });

  /// The active segment's link. The panel follows it, so the panel moves if the
  /// bar ever does.
  final LayerLink link;
  final SearchPopoverAlign align;

  /// Global Y at which the dim begins — the header's bottom edge.
  final double scrimTop;

  final VoidCallback onDismiss;

  /// Fixed, not a maximum: a panel that resized to its contents would jump
  /// under the cursor as suggestions arrive, and the anchor maths needs a width
  /// it can rely on.
  final double width;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final (target, follower) = switch (align) {
      SearchPopoverAlign.left => (Alignment.bottomLeft, Alignment.topLeft),
      SearchPopoverAlign.center => (
          Alignment.bottomCenter,
          Alignment.topCenter
        ),
      SearchPopoverAlign.right => (Alignment.bottomRight, Alignment.topRight),
    };

    return Stack(
      children: [
        Positioned(
          top: scrimTop,
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Color(0x14000000)),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          targetAnchor: target,
          followerAnchor: follower,
          // Clear of the pill's own shadow, so the two do not merge into one
          // grey smudge.
          offset: const Offset(0, 12),
          // No Align around this. An Align with no size factor expands to the
          // loose constraints it is given — the whole overlay — so the follower
          // measured 1440 wide and `followerAnchor: topRight` lined THAT corner
          // up with the segment, throwing the panel hundreds of pixels off the
          // left of the window. The follower has to size to the panel.
          child: _Panel(
            width: width,
            onDismiss: onDismiss,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.width,
    required this.onDismiss,
    required this.child,
  });

  final double width;
  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // A short window must not clip a panel — the calendar is the tall one — so
    // the height is capped against the viewport and the content scrolls inside.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
      },
      child: FocusScope(
        // Traversal stays inside the panel while it is open, so Tab does not
        // walk out into the feed behind the scrim.
        //
        // autofocus matters as much as the scope: CallbackShortcuts only fires
        // for a key event that reaches it through the focus chain, so a panel
        // with nothing focused inside it (the Who counter, say) would ignore
        // Escape entirely.
        autofocus: true,
        child: Material(
          color: AppColors.surface,
          elevation: 0,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: width,
            constraints: BoxConstraints(maxHeight: maxHeight),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppColors.outline, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A −/+ stepper row: label, description, and the two round buttons.
///
/// Lives here rather than in the Who panel because the Filters panel wants the
/// same control, and because a stepper whose buttons disable at their bounds is
/// exactly the sort of thing that gets re-implemented slightly differently the
/// second time.
class SearchStepperRow extends StatelessWidget {
  const SearchStepperRow({
    super.key,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
  });

  final String label;
  final String description;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),
          _StepButton(
            icon: Icons.remove,
            // Disabled rather than hidden at the bound: a button that vanishes
            // moves the number under the cursor.
            onTap: value > min ? () => onChanged(value - 1) : null,
            semanticLabel: 'One fewer $label',
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            onTap: value < max ? () => onChanged(value + 1) : null,
            semanticLabel: 'One more $label',
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: MouseRegion(
              cursor:
                  enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: enabled ? AppColors.inkMuted : AppColors.outline,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: enabled ? AppColors.ink : AppColors.outline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
