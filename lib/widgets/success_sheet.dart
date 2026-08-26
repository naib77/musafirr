import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// A modern, celebratory confirmation sheet for "done!" moments — booking
/// requests, submissions, etc. Replaces flat success banners for actions that
/// deserve a beat of delight.
///
/// Shows an animated check (ring pulse + spring-in tick), a title/message, and
/// a primary CTA. Call [SuccessSheet.show]:
///
/// ```dart
/// await SuccessSheet.show(
///   context,
///   title: 'Request sent!',
///   message: 'Your booking is awaiting host confirmation.',
///   primaryLabel: 'Got it',
/// );
/// ```
class SuccessSheet extends StatefulWidget {
  const SuccessSheet({
    super.key,
    required this.title,
    required this.message,
    this.accent,
    this.icon = Icons.check_rounded,
    this.primaryLabel = 'Done',
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.autoDismiss = const Duration(seconds: 4),
  });

  final String title;
  final String message;

  /// The sheet's celebratory colour. Null means "whatever the active theme calls
  /// success" — resolved in [build] rather than defaulted here, because
  /// `AppColors.success` is now a getter over the admin-selected palette and a
  /// default parameter value has to be a compile-time constant.
  final Color? accent;
  final IconData icon;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// If non-null, the sheet closes itself after this delay. The grab handle and
  /// the X let the user dismiss sooner; tapping outside also dismisses.
  final Duration? autoDismiss;

  /// Presents the sheet as a rounded modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    Color? accent,
    IconData icon = Icons.check_rounded,
    String primaryLabel = 'Done',
    VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    Duration? autoDismiss = const Duration(seconds: 4),
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => SuccessSheet(
        title: title,
        message: message,
        accent: accent,
        icon: icon,
        primaryLabel: primaryLabel,
        onPrimary: onPrimary,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
        autoDismiss: autoDismiss,
      ),
    );
  }

  @override
  State<SuccessSheet> createState() => _SuccessSheetState();
}

class _SuccessSheetState extends State<SuccessSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _tick; // spring-in checkmark
  late final Animation<double> _ring; // expanding ring
  late final Animation<double> _content; // text/buttons fade-up
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _tick = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
    );
    _ring = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.1, 0.7, curve: Curves.easeOut),
    );
    _content = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
    );
    _controller.forward();

    // Auto-dismiss after the configured delay. If the user dismisses sooner
    // (X / Got it / scrim), the State unmounts and the guard below no-ops.
    final autoDismiss = widget.autoDismiss;
    if (autoDismiss != null) {
      _autoDismissTimer = Timer(autoDismiss, () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  /// Single dismissal path for the X and the primary/secondary buttons, so the
  /// auto-dismiss timer can never double-pop.
  void _dismiss({VoidCallback? then}) {
    _autoDismissTimer?.cancel();
    Navigator.of(context).pop();
    then?.call();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Resolved per build, not per construction: the active palette can change
    // under a live sheet when the admin's theme lands mid-session.
    final accent = widget.accent ?? AppColors.success;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grab handle (centered) with a close button pinned to the right.
          SizedBox(
            height: 28,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Material(
                    color: AppColors.surfaceMuted,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _dismiss,
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded,
                            size: 18, color: AppColors.inkMuted),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Animated success badge
          SizedBox(
            height: 104,
            width: 104,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Expanding, fading ring
                    Opacity(
                      opacity: (1 - _ring.value).clamp(0.0, 1.0) * 0.5,
                      child: Transform.scale(
                        scale: 0.7 + _ring.value * 0.9,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ),
                    // Solid badge
                    Transform.scale(
                      scale: _tick.value.clamp(0.0, 1.0),
                      child: child,
                    ),
                  ],
                );
              },
              child: Container(
                height: 76,
                width: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      accent,
                      Color.lerp(accent, Colors.black, 0.18)!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title + message + actions fade up together
          FadeTransition(
            opacity: _content,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.18),
                end: Offset.zero,
              ).animate(_content),
              child: Column(
                children: [
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkMuted,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _dismiss(then: widget.onPrimary),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        minimumSize: const Size.fromHeight(54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        widget.primaryLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (widget.secondaryLabel != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => _dismiss(then: widget.onSecondary),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.inkMuted,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text(widget.secondaryLabel!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
