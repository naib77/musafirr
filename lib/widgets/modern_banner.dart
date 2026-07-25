import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Severity of a toast, drives its accent color + icon.
enum _ToastType { success, error, warning, info, neutral }

/// Shows modern, animated floating toasts at the top of the screen.
///
/// API is unchanged from the old MaterialBanner version — every existing
/// `ModernBanner.showSuccess/showError/...` call upgrades for free.
class ModernBanner {
  ModernBanner._();

  static _ToastHandle? _current;

  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    double topOffset = 0,
  }) =>
      _show(context, message, _ToastType.success, duration, actionLabel, onAction,
          topOffset: topOffset);

  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _show(context, message, _ToastType.error, duration, actionLabel, onAction);

  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _show(context, message, _ToastType.info, duration, actionLabel, onAction);

  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _show(context, message, _ToastType.warning, duration, actionLabel, onAction);

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) =>
      _show(context, message, _ToastType.neutral, duration, actionLabel, onAction);

  static void _show(
    BuildContext context,
    String message,
    _ToastType type,
    Duration duration,
    String? actionLabel,
    VoidCallback? onAction, {
    double topOffset = 0,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    // Replace any visible toast immediately.
    _current?.remove();

    late final _ToastHandle handle;
    final entry = OverlayEntry(
      builder: (_) => _Toast(
        message: message,
        type: type,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        topOffset: topOffset,
        onDismissed: () {
          if (identical(_current, handle)) _current = null;
          handle.remove();
        },
      ),
    );
    handle = _ToastHandle(entry);
    _current = handle;
    overlay.insert(entry);
  }
}

/// Idempotent wrapper so an entry is never removed twice (timer vs. replace).
class _ToastHandle {
  _ToastHandle(this.entry);
  final OverlayEntry entry;
  bool _removed = false;

  void remove() {
    if (_removed) return;
    _removed = true;
    entry.remove();
  }
}

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
    this.topOffset = 0,
  });

  final String message;
  final _ToastType type;
  final Duration duration;
  final VoidCallback onDismissed;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double topOffset;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    _controller.forward();
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) {
      widget.onDismissed();
      return;
    }
    await _controller.reverse();
    widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  ({Color color, IconData icon}) get _style => switch (widget.type) {
        _ToastType.success => (color: AppColors.success, icon: Icons.check_circle_rounded),
        _ToastType.error => (color: AppColors.error, icon: Icons.error_rounded),
        _ToastType.warning => (color: AppColors.warning, icon: Icons.warning_rounded),
        _ToastType.info => (color: AppColors.info, icon: Icons.info_rounded),
        _ToastType.neutral => (color: AppColors.brand, icon: Icons.notifications_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final s = _style;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 8 + widget.topOffset, 12, 0),
          child: FadeTransition(
            opacity: _controller,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.4),
                end: Offset.zero,
              ).animate(_curve),
              child: _card(s),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(({Color color, IconData icon}) s) {
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: _dismiss,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border(left: BorderSide(color: s.color, width: 4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: s.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(s.icon, color: s.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ),
              if (widget.actionLabel != null && widget.onAction != null)
                TextButton(
                  onPressed: () {
                    widget.onAction!.call();
                    _dismiss();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: s.color,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(widget.actionLabel!),
                )
              else
                IconButton(
                  onPressed: _dismiss,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppColors.inkMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
