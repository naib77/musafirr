import 'dart:math' as math;

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

/// How long the panel takes to travel between segments. Long enough to read as
/// motion, short enough not to get in the way of a second click.
const Duration kSearchPanelMotion = Duration(milliseconds: 260);

/// The floating panel behind the search bar.
///
/// ## One panel that moves, not four that appear
///
/// The first version anchored a separate panel under each segment with a
/// [CompositedTransformFollower] and rebuilt it from scratch on every switch.
/// Position, width and contents all changed in the same frame, which is exactly
/// what "it flicks" describes — there was no transition, just a cut. Airbnb's
/// panel is a single card that slides along the bar and morphs.
///
/// So this is one [AnimatedPositioned] card whose left edge and width animate,
/// with an [AnimatedSwitcher] cross-fading the contents. Both panels are
/// briefly on screen together, which is what makes the change read as movement
/// rather than as a flash.
///
/// ## Why it takes measured rectangles instead of a LayerLink
///
/// A follower cannot be animated between two different links, and animating a
/// position needs the geometry as *numbers*. Those are measured after layout by
/// `SearchPill` and passed in — never read during build, which is what the
/// previous version did and is the one mechanism here capable of throwing
/// during a rebuild. An exception in this subtree paints a full-screen dark red
/// [ErrorWidget], because the overlay child covers the window.
///
/// ## The scrim starts below the bar, deliberately
///
/// Airbnb dims the page behind an open panel but leaves the bar itself bright,
/// so you can see which segment is active and click straight to another one. A
/// full-screen scrim would grey the header too and make the whole bar read as
/// disabled.
class SearchPopover extends StatelessWidget {
  const SearchPopover({
    super.key,
    required this.anchor,
    required this.scrimTop,
    required this.width,
    required this.align,
    required this.contentKey,
    required this.onDismiss,
    required this.child,
  });

  /// The active segment's rectangle, in global coordinates.
  final Rect anchor;

  /// Global Y at which the dim begins — the bar's bottom edge.
  final double scrimTop;

  /// Fixed, not a maximum: a panel that resized to its contents would jump
  /// under the cursor as suggestions arrive, and the travel animation needs a
  /// width it can tween.
  final double width;

  final SearchPopoverAlign align;

  /// Identifies the contents, so the cross-fade knows one panel from another.
  final Object contentKey;

  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    // A short window must not clip a panel — the calendar is the tall one — so
    // the height is capped and the content scrolls inside.
    final maxHeight = screen.height * 0.72;

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
            child: const ColoredBox(
              key: ValueKey('search-scrim'),
              color: Color(0x14000000),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: kSearchPanelMotion,
          curve: Curves.easeOutCubic,
          left: _left(screen.width),
          // Clear of the bar's own shadow, so the two do not merge into one
          // grey smudge.
          top: anchor.bottom + 12,
          width: width,
          child: _Panel(
            maxHeight: maxHeight,
            onDismiss: onDismiss,
            contentKey: contentKey,
            child: child,
          ),
        ),
      ],
    );
  }

  double _left(double screenWidth) {
    final raw = switch (align) {
      SearchPopoverAlign.left => anchor.left,
      SearchPopoverAlign.center => anchor.center.dx - width / 2,
      SearchPopoverAlign.right => anchor.right - width,
    };
    // A panel must never hang off the window, however the bar is laid out.
    const margin = 12.0;
    return raw.clamp(margin, math.max(margin, screenWidth - width - margin));
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.maxHeight,
    required this.onDismiss,
    required this.contentKey,
    required this.child,
  });

  final double maxHeight;
  final VoidCallback onDismiss;
  final Object contentKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
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
          key: const ValueKey('search-panel'),
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Container(
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
            // The height changes between panels too. Animating it as well means
            // the card grows and shrinks rather than snapping, which is the
            // other half of what made the switch feel like a cut.
            child: AnimatedSize(
              duration: kSearchPanelMotion,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                // topCenter, not the default centre: the two panels are
                // different heights, and centring them would make the outgoing
                // one drift upwards as it fades.
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    ...previous,
                    if (current != null) current,
                  ],
                ),
                child: KeyedSubtree(key: ValueKey(contentKey), child: child),
              ),
            ),
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
