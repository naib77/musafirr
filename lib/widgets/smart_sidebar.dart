import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';
import '../services/pwa/pwa_install_service.dart';

/// One tile in the smart sidebar's shortcut grid.
@immutable
class SmartSidebarShortcut {
  const SmartSidebarShortcut({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.accent,
    this.badge = false,
  });

  final IconData icon;

  /// Kept to one short word — three tiles share a ~270px row.
  final String label;
  final VoidCallback onTap;
  final Color accent;

  /// Draws an unread dot on the tile (Messages, Notifications).
  final bool badge;
}

/// An OPPO-style smart sidebar for mobile web.
///
/// A slim handle rides the right edge; swiping it inward (or tapping it) pulls
/// a floating quick-access panel over the app — install the PWA, jump to any
/// tab. Closing works by swiping back, tapping the scrim, pressing Escape, or
/// the system back button.
///
/// Mounts only where it earns its place: `kIsWeb` and a narrow viewport. On
/// desktop the navigation rail already exposes every destination, and on native
/// there is no PWA to install — in both cases [child] is returned untouched, so
/// wrapping is free.
///
/// The grab zone is deliberately a short band rather than the full edge: a
/// full-height strip would swallow horizontal drags meant for carousels, maps
/// and the browser's own edge gestures.
class SmartSidebar extends StatefulWidget {
  const SmartSidebar({
    super.key,
    required this.child,
    required this.shortcuts,
    this.enabled = true,
  });

  final Widget child;
  final List<SmartSidebarShortcut> shortcuts;

  /// Escape hatch for screens that need the right edge to themselves.
  final bool enabled;

  @override
  State<SmartSidebar> createState() => _SmartSidebarState();
}

class _SmartSidebarState extends State<SmartSidebar>
    with SingleTickerProviderStateMixin {
  /// Preferred panel width; narrowed on small phones by [_resolveExtent].
  static const double _preferredWidth = 296;

  /// Gap between the panel and the screen edge — the floating look.
  static const double _panelInset = 12;

  /// Fling speed (px/s) past which direction wins over position.
  static const double _flingThreshold = 320;

  /// Distance from the top of the viewport (below the status bar) to the top
  /// of the pill — and of the panel it pulls in. Adds up the search row band
  /// that heads every tab (10 top inset + 44 field + 8 bottom inset + the 1px
  /// divider), so the pill begins immediately under it with no gap, rather
  /// than drifting down the screen the way a proportional anchor did.
  static const double _handleTopOffset = 63;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );

  /// Panel width for the current viewport. Set in [build] and read by the drag
  /// handlers to convert pixels into controller progress.
  double _extent = _preferredWidth;

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _open() => _anim.animateTo(
        1,
        duration: _reduceMotion ? Duration.zero : null,
        curve: Curves.easeOutCubic,
      );

  void _close() => _anim.animateBack(
        0,
        duration: _reduceMotion ? Duration.zero : null,
        curve: Curves.easeInCubic,
      );

  // Dragging left (negative dx) pulls the panel in; the controller follows the
  // finger 1:1 — no curve — so the panel stays glued to the touch point.
  void _onDragUpdate(DragUpdateDetails details) {
    _anim.value -= (details.primaryDelta ?? 0) / _extent;
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity.abs() > _flingThreshold) {
      // Normalise px/s into progress/s, flipping sign: leftward opens.
      _anim.fling(velocity: -velocity / _extent);
      return;
    }
    _anim.value > 0.5 ? _open() : _close();
  }

  /// Closes first so the panel slides away over the destination, rather than
  /// the tab switching behind a still-open panel.
  void _runShortcut(SmartSidebarShortcut shortcut) {
    _close();
    shortcut.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && kIsWeb && !Responsive.isWide(context);
    if (!active) return widget.child;

    _extent = _resolveExtent(MediaQuery.sizeOf(context).width);

    // Pinned a fixed distance below the status bar rather than to a fraction
    // of the height, so the handle lands just under the search bar on every
    // viewport instead of sliding toward the middle on tall ones.
    final double handleTop =
        MediaQuery.paddingOf(context).top + _handleTopOffset;

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(child: _buildScrim()),
        _buildPanelLayer(handleTop),
        _buildHandle(handleTop),
      ],
    );
  }

  /// Leaves room for the scrim to read as "the app is still back there" on
  /// small phones, while capping the panel on larger ones.
  double _resolveExtent(double screenWidth) =>
      math.min(_preferredWidth, screenWidth - 72);

  // ── Layers ────────────────────────────────────────────────────────────────

  Widget _buildScrim() {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final progress = _anim.value;
        return IgnorePointer(
          ignoring: progress <= 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: ColoredBox(
              color: AppColors.ink.withValues(alpha: 0.34 * progress),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPanelLayer(double top) {
    // Top-aligned with the handle, so the panel appears to come out of the
    // thing you just pulled; the run to the bottom edge is what a tall
    // shortcut grid scrolls inside.
    return Positioned(
      top: top,
      right: 0,
      bottom: 0,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final progress = _anim.value;
          if (progress <= 0) return const SizedBox.shrink();
          return FractionalTranslation(
            // The child's own width includes [_panelInset], so a full 1.0
            // translation parks it completely off-screen.
            translation: Offset(1 - progress, 0),
            child: child,
          );
        },
        child: RepaintBoundary(child: _buildPanel()),
      ),
    );
  }

  Widget _buildHandle(double top) {
    return Positioned(
      top: top,
      right: 0,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          // Fades out over the first half of the pull, by which point the
          // panel itself is the thing under the finger.
          final visibility = (1 - _anim.value * 2).clamp(0.0, 1.0);
          return IgnorePointer(
            ignoring: visibility == 0,
            child: Opacity(opacity: visibility, child: child),
          );
        },
        child: Semantics(
          container: true,
          button: true,
          label: 'Quick access',
          hint: 'Swipe in from the right edge to open',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _open,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: const SizedBox(
              // 28x104: comfortably past the 44px minimum in the axis that
              // matters, without claiming the whole edge.
              width: 28,
              height: 104,
              // Top-right: flush against the screen edge (centring it in the
              // grab zone left a gap that read as floating loose of the edge)
              // and top-aligned so the visible pill — not the invisible grab
              // zone — is what lines up with the search row. The zone runs on
              // below the pill, where the extra slop is easiest to reach.
              child: Align(
                alignment: Alignment.topRight,
                child: _HandlePill(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Panel ─────────────────────────────────────────────────────────────────

  Widget _buildPanel() {
    return Padding(
      padding: const EdgeInsets.only(right: _panelInset),
      child: SizedBox(
        width: _extent,
        child: SafeArea(
          minimum: const EdgeInsets.symmetric(vertical: 16),
          // Shrink-wraps to the card, so the panel stays vertically centred;
          // only scrolls when a tall shortcut grid meets a short viewport.
          child: SingleChildScrollView(
            child: PopScope(
              // System back closes the panel instead of falling through to the
              // shell's own back handling.
              canPop: false,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) _close();
              },
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): _close,
                },
                child: Focus(
                  autofocus: true,
                  child: GestureDetector(
                    // Swiping the panel itself back to the right closes it.
                    onHorizontalDragUpdate: _onDragUpdate,
                    onHorizontalDragEnd: _onDragEnd,
                    child: _panelCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Frosted, but at an opacity that keeps text at full contrast —
            // a barely-there glass card is unreadable over a light UI.
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.75),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.18),
                blurRadius: 34,
                offset: const Offset(-6, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _panelHeader(),
                const SizedBox(height: 14),
                _InstallSection(onDone: _close),
                if (widget.shortcuts.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const _PanelLabel('Jump to'),
                  const SizedBox(height: 10),
                  _shortcutGrid(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _panelHeader() {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Quick access',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: -0.2,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          height: 44,
          child: IconButton(
            onPressed: _close,
            padding: EdgeInsets.zero,
            iconSize: 20,
            color: AppColors.inkMuted,
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }

  Widget _shortcutGrid() {
    // Three per row, sized off the card's inner width so the tiles fill it
    // exactly at any panel width.
    const columns = 3;
    const gap = 8.0;
    final tileWidth = (_extent - 32 - gap * (columns - 1)) / columns;

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final shortcut in widget.shortcuts)
          SizedBox(
            width: tileWidth,
            child: _ShortcutTile(
              shortcut: shortcut,
              onTap: () => _runShortcut(shortcut),
            ),
          ),
      ],
    );
  }
}

/// The edge affordance: a slim translucent pill, flat against the right edge.
class _HandlePill extends StatelessWidget {
  const _HandlePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.ink.withValues(alpha: 0.26),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.16),
            blurRadius: 6,
            offset: const Offset(-1, 2),
          ),
        ],
      ),
    );
  }
}

class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: AppColors.inkMuted,
      ),
    );
  }
}

/// The install-the-app slot, which renders whatever the browser actually
/// supports — a real prompt, iOS instructions, or a quiet "installed" note.
class _InstallSection extends StatefulWidget {
  const _InstallSection({required this.onDone});

  /// Called after a successful install, to dismiss the panel.
  final VoidCallback onDone;

  @override
  State<_InstallSection> createState() => _InstallSectionState();
}

class _InstallSectionState extends State<_InstallSection> {
  bool _busy = false;

  Future<void> _install() async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await PwaInstallService.instance.install();
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome == PwaInstallOutcome.accepted) widget.onDone();
  }

  void _showIosSteps() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const _IosInstallSteps(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PwaInstallService.instance,
      builder: (context, _) {
        switch (PwaInstallService.instance.mode) {
          case PwaInstallMode.prompt:
            return _InstallCard(
              icon: Icons.install_mobile_rounded,
              title: 'Install Musaafir',
              subtitle: 'Full-screen app, faster launches',
              busy: _busy,
              onTap: _install,
            );
          case PwaInstallMode.manualIos:
            return _InstallCard(
              icon: Icons.ios_share_rounded,
              title: 'Add to Home Screen',
              subtitle: 'Two taps in Safari — see how',
              busy: false,
              onTap: _showIosSteps,
            );
          case PwaInstallMode.installed:
            return const _InstalledNote();
          case PwaInstallMode.unsupported:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

/// The panel's one hero action — brand gradient, deliberately louder than the
/// neutral shortcut tiles below it.
class _InstallCard extends StatelessWidget {
  const _InstallCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Disabled while the browser dialog is up, so a double tap can't fire
        // a second prompt against an already-consumed event.
        onTap: busy ? null : onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: busy
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        )
                      : const Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown once the app is installed — quiet, but present, so someone who swiped
/// in looking for the install button gets an answer instead of a blank space.
class _InstalledNote extends StatelessWidget {
  const _InstalledNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'App installed',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IosInstallSteps extends StatelessWidget {
  const _IosInstallSteps();

  @override
  Widget build(BuildContext context) {
    const steps = <(IconData, String)>[
      (Icons.ios_share_rounded, 'Tap the Share button in Safari\'s toolbar'),
      (Icons.add_box_outlined, 'Scroll down and choose "Add to Home Screen"'),
      (Icons.check_rounded, 'Tap "Add" — Musaafir lands on your home screen'),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Musaafir to your Home Screen',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Safari has no one-tap install, so it takes two taps.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 18),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.brand.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child:
                          Icon(steps[i].$1, size: 18, color: AppColors.brand),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(
                          steps[i].$2,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.shortcut, required this.onTap});

  final SmartSidebarShortcut shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: shortcut.label,
      child: Material(
        color: AppColors.surfaceMuted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: shortcut.badge,
                  smallSize: 7,
                  backgroundColor: AppColors.error,
                  child: Icon(shortcut.icon, size: 22, color: shortcut.accent),
                ),
                const SizedBox(height: 7),
                Text(
                  shortcut.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
