import 'package:flutter/material.dart';

/// A utility class for showing modern, eye-catching MaterialBanners
/// that appear at the top of the screen.
class ModernBanner {
  ModernBanner._();

  /// Shows a success banner with green theme
  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showBanner(
      context,
      message: message,
      icon: Icons.check_circle_rounded,
      backgroundColor: const Color(0xFF059669), // Emerald 600
      iconColor: Colors.white,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Shows an error banner with red theme
  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 4),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showBanner(
      context,
      message: message,
      icon: Icons.error_rounded,
      backgroundColor: const Color(0xFFDC2626), // Red 600
      iconColor: Colors.white,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Shows an info banner with blue theme
  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showBanner(
      context,
      message: message,
      icon: Icons.info_rounded,
      backgroundColor: const Color(0xFF2563EB), // Blue 600
      iconColor: Colors.white,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Shows a warning banner with amber/orange theme
  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showBanner(
      context,
      message: message,
      icon: Icons.warning_rounded,
      backgroundColor: const Color(0xFFD97706), // Amber 600
      iconColor: Colors.white,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Shows a neutral/default banner
  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _showBanner(
      context,
      message: message,
      icon: Icons.notifications_rounded,
      backgroundColor: const Color(0xFF475569), // Slate 600
      iconColor: Colors.white,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void _showBanner(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color backgroundColor,
    required Color iconColor,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    // Capture messenger before any async operations
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    // Clear any existing banners
    messenger.clearMaterialBanners();

    messenger.showMaterialBanner(
      MaterialBanner(
        elevation: 4,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leadingPadding: EdgeInsets.zero,
        backgroundColor: backgroundColor,
        shadowColor: Colors.black26,
        dividerColor: Colors.transparent,
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (onAction != null && actionLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _BannerActionButton(
                label: actionLabel,
                onPressed: () {
                  messenger.hideCurrentMaterialBanner();
                  onAction();
                },
                isPrimary: true,
              ),
            ),
          _BannerActionButton(
            label: 'Dismiss',
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            isPrimary: false,
          ),
        ],
      ),
    );

    // Auto-dismiss after duration
    Future.delayed(duration, () {
      messenger.hideCurrentMaterialBanner();
    });
  }
}

class _BannerActionButton extends StatelessWidget {
  const _BannerActionButton({
    required this.label,
    required this.onPressed,
    required this.isPrimary,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isPrimary
          ? Colors.white
          : Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: isPrimary ? Colors.black87 : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
