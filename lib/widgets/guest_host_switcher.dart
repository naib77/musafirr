import 'package:flutter/material.dart';

import '../state/app_mode_state.dart';
import 'modern_banner.dart';

/// Uber-like tab switcher for Guest/Host modes
class GuestHostSwitcher extends StatelessWidget {
  const GuestHostSwitcher({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.hasHostNotification = false,
  });

  final AppMode mode;
  final ValueChanged<AppMode> onModeChanged;
  final bool hasHostNotification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  // Guest tab
                  Expanded(
                    child: _ModeTab(
                      icon: Icons.luggage,
                      label: 'Guest',
                      isSelected: mode == AppMode.guest,
                      onTap: () => _switchTo(context, AppMode.guest),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Host tab
                  Expanded(
                    child: _ModeTab(
                      icon: Icons.home,
                      label: 'Host',
                      isSelected: mode == AppMode.host,
                      hasNotification: hasHostNotification,
                      onTap: () => _switchTo(context, AppMode.host),
                    ),
                  ),
                ],
              ),
            ),
            // Underline indicator
            Stack(
              children: [
                // Background line
                Container(
                  height: 3,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
                // Animated indicator
                AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: mode == AppMode.guest
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Switches mode and shows the app's modern floating toast explaining the
  /// mode you just moved into. No-op if you tap the tab you're already on.
  void _switchTo(BuildContext context, AppMode target) {
    if (target == mode) return;
    onModeChanged(target);

    ModernBanner.showSuccess(
      context,
      target == AppMode.host
          ? 'Switched to Host — manage your listings & bookings.'
          : 'Switched to Guest — find & book stays.',
      duration: const Duration(seconds: 2),
      // Drop the toast just below the Guest/Host tab strip instead of over it.
      topOffset: 52,
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.hasNotification = false,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool hasNotification;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
                // Notification dot
                if (hasNotification && !isSelected)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
