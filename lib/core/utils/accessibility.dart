import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

/// Accessibility utilities for better screen reader support
class A11y {
  A11y._();

  /// Announce a message to screen readers
  static void announce(BuildContext context, String message) {
    SemanticsService.announce(message, Directionality.of(context));
  }

  /// Check if screen reader is active
  static bool isScreenReaderActive(BuildContext context) {
    return MediaQuery.of(context).accessibleNavigation;
  }

  /// Check if reduce motion is enabled
  static bool isReduceMotionEnabled(BuildContext context) {
    return MediaQuery.of(context).disableAnimations;
  }

  /// Check if bold text is enabled
  static bool isBoldTextEnabled(BuildContext context) {
    return MediaQuery.of(context).boldText;
  }

  /// Get the appropriate animation duration based on accessibility settings
  static Duration getAnimationDuration(
    BuildContext context, {
    Duration normal = const Duration(milliseconds: 300),
    Duration reduced = Duration.zero,
  }) {
    return isReduceMotionEnabled(context) ? reduced : normal;
  }

  /// Get the appropriate animation curve based on accessibility settings
  static Curve getAnimationCurve(
    BuildContext context, {
    Curve normal = Curves.easeInOut,
    Curve reduced = Curves.linear,
  }) {
    return isReduceMotionEnabled(context) ? reduced : normal;
  }
}

/// Extension for semantic widgets
extension SemanticWidgetExtension on Widget {
  /// Add semantic label for screen readers
  Widget semanticLabel(String label) {
    return Semantics(
      label: label,
      child: this,
    );
  }

  /// Mark as button for screen readers
  Widget semanticButton({
    required String label,
    VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Semantics(
      button: true,
      label: label,
      enabled: enabled,
      onTap: onTap,
      child: this,
    );
  }

  /// Mark as header for screen readers
  Widget semanticHeader(String label) {
    return Semantics(
      header: true,
      label: label,
      child: this,
    );
  }

  /// Mark as image for screen readers
  Widget semanticImage(String description) {
    return Semantics(
      image: true,
      label: description,
      child: this,
    );
  }

  /// Exclude from semantics
  Widget excludeSemantics() {
    return ExcludeSemantics(child: this);
  }

  /// Mark as live region for dynamic content
  Widget semanticLiveRegion({
    required String label,
    bool polite = true,
  }) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: this,
    );
  }
}

/// Accessible button that ensures proper contrast and touch target size
class AccessibleButton extends StatelessWidget {
  const AccessibleButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.semanticLabel,
    this.minTouchTargetSize = 48,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final double minTouchTargetSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: onPressed != null,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minTouchTargetSize,
          minHeight: minTouchTargetSize,
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// Accessible icon button with proper touch target
class AccessibleIconButton extends StatelessWidget {
  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 48,
    this.iconSize = 24,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      enabled: onPressed != null,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          icon: Icon(icon, size: iconSize),
          onPressed: onPressed,
          color: color,
          tooltip: semanticLabel,
        ),
      ),
    );
  }
}

/// Text with automatic scaling and accessibility considerations
class AccessibleText extends StatelessWidget {
  const AccessibleText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.semanticLabel,
    this.maxScaleFactor = 2.0,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final String? semanticLabel;
  final double maxScaleFactor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? text,
      child: Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        textAlign: textAlign,
        textScaler: TextScaler.linear(
          MediaQuery.textScalerOf(context)
              .scale(1.0)
              .clamp(1.0, maxScaleFactor),
        ),
      ),
    );
  }
}

/// Container that announces content changes
class AnnouncingContainer extends StatefulWidget {
  const AnnouncingContainer({
    super.key,
    required this.child,
    required this.announcement,
    this.announceOnChange = true,
  });

  final Widget child;
  final String announcement;
  final bool announceOnChange;

  @override
  State<AnnouncingContainer> createState() => _AnnouncingContainerState();
}

class _AnnouncingContainerState extends State<AnnouncingContainer> {
  String? _previousAnnouncement;

  @override
  void didUpdateWidget(AnnouncingContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.announceOnChange &&
        widget.announcement != _previousAnnouncement) {
      _previousAnnouncement = widget.announcement;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          A11y.announce(context, widget.announcement);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: widget.child,
    );
  }
}

/// Focus-aware widget that tracks focus for accessibility
class FocusableWidget extends StatefulWidget {
  const FocusableWidget({
    super.key,
    required this.child,
    required this.focusedChild,
    this.onFocusChange,
    this.autofocus = false,
  });

  final Widget child;
  final Widget focusedChild;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;

  @override
  State<FocusableWidget> createState() => _FocusableWidgetState();
}

class _FocusableWidgetState extends State<FocusableWidget> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _isFocused = focused);
        widget.onFocusChange?.call(focused);
      },
      child: _isFocused ? widget.focusedChild : widget.child,
    );
  }
}

/// Skip link for keyboard navigation
class SkipLink extends StatelessWidget {
  const SkipLink({
    super.key,
    required this.targetKey,
    this.label = 'Skip to main content',
  });

  final GlobalKey targetKey;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Focus(
        child: Builder(
          builder: (context) {
            final hasFocus = Focus.of(context).hasFocus;
            if (!hasFocus) return const SizedBox.shrink();

            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Theme.of(context).colorScheme.primary,
                child: InkWell(
                  onTap: () {
                    final target = targetKey.currentContext;
                    if (target != null) {
                      Scrollable.ensureVisible(target);
                      FocusScope.of(context).requestFocus(
                        Focus.of(target).nearestScope,
                      );
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      label,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Color contrast checker
class ContrastChecker {
  ContrastChecker._();

  /// Calculate relative luminance
  static double relativeLuminance(Color color) {
    double r = color.red / 255;
    double g = color.green / 255;
    double b = color.blue / 255;

    r = r <= 0.03928 ? r / 12.92 : ((r + 0.055) / 1.055).pow(2.4);
    g = g <= 0.03928 ? g / 12.92 : ((g + 0.055) / 1.055).pow(2.4);
    b = b <= 0.03928 ? b / 12.92 : ((b + 0.055) / 1.055).pow(2.4);

    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Calculate contrast ratio between two colors
  static double contrastRatio(Color foreground, Color background) {
    final l1 = relativeLuminance(foreground);
    final l2 = relativeLuminance(background);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  /// Check if contrast meets WCAG AA standard (4.5:1 for normal text)
  static bool meetsAA(Color foreground, Color background) {
    return contrastRatio(foreground, background) >= 4.5;
  }

  /// Check if contrast meets WCAG AAA standard (7:1 for normal text)
  static bool meetsAAA(Color foreground, Color background) {
    return contrastRatio(foreground, background) >= 7.0;
  }

  /// Check if contrast meets WCAG AA for large text (3:1)
  static bool meetsAALarge(Color foreground, Color background) {
    return contrastRatio(foreground, background) >= 3.0;
  }

  /// Get appropriate text color for a background
  static Color getTextColor(Color background) {
    final luminance = relativeLuminance(background);
    return luminance > 0.179 ? Colors.black : Colors.white;
  }
}

extension _DoubleExtension on double {
  double pow(double exponent) {
    return this == 0
        ? 0
        : (this > 0 ? 1 : -1) * (abs()).toDouble().pow2(exponent);
  }

  double pow2(double exponent) {
    return exponent == 0 ? 1 : this * pow2(exponent - 1);
  }
}
