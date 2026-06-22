import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The single, app-wide page header that sits at the top of every primary
/// tab (just below the Guest/Host switcher).
///
/// Before this existed, some tabs used a flat bold "slim header" while others
/// used a Material [AppBar], so titles rendered at different sizes/weights and
/// the screens felt inconsistent. [AppPageHeader] unifies them: one title
/// treatment, one action-chip style, one rhythm.
///
/// It is intentionally flat (no elevation) and applies **no** top [SafeArea] —
/// the Guest/Host switcher is the single top-inset consumer (see
/// `main_shell.dart`), so headers below it must not re-add that padding.
///
/// ```dart
/// AppPageHeader(
///   title: 'Wishlists',
///   subtitle: 'Places you’ve saved',
///   actions: [
///     HeaderActionButton(
///       icon: Icons.chat_bubble_outline,
///       badgeCount: unread,
///       onTap: onOpenInbox,
///       tooltip: 'Messages',
///     ),
///     bell, // any trailing widget, e.g. AnimatedNotificationBell
///   ],
///   bottom: mySegmentedControl, // optional tabs under the title
/// )
/// ```
class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String? subtitle;

  /// Trailing action widgets (messages, notification bell, …). Prefer
  /// [HeaderActionButton] so every action chip matches.
  final List<Widget> actions;

  /// Optional control rendered below the title row — e.g. a tab/segmented
  /// control. Lets tabbed screens share the exact same header.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              subtitle == null ? 12 : 14,
              12,
              subtitle == null ? 12 : 14,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          height: 1.05,
                          color: AppColors.ink,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.inkMuted,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        actions[i],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (bottom != null) bottom!,
        ],
      ),
    );
  }
}

/// A soft, circular icon button for [AppPageHeader.actions] — matches the
/// rounded-icon language already used on the Explore search bar. Shows an
/// optional unread [badgeCount].
class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final int badgeCount;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget child = Material(
      color: AppColors.surfaceMuted,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: AppColors.ink),
        ),
      ),
    );

    if (badgeCount > 0) {
      child = Badge(
        label: Text(badgeCount > 99 ? '99+' : '$badgeCount'),
        child: child,
      );
    }

    if (tooltip != null) {
      child = Tooltip(message: tooltip!, child: child);
    }

    return child;
  }
}
