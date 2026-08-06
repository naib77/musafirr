import 'package:flutter/material.dart';

/// Adds a pointer cursor and a subtle scale-up while a mouse hovers over
/// [child]. On touch devices there is no hover, so this is a complete no-op —
/// safe to apply on every platform. Used to give desktop web cards a modern
/// "lift" affordance without touching the mobile experience.
class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.scale = 1.03,
  });

  final Widget child;

  /// Scale applied on hover. Pass 1.0 for cursor-only feedback (e.g. inside a
  /// tight, clipping horizontal list where a scale would be cropped).
  final double scale;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
