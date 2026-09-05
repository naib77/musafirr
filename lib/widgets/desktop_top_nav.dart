import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'app_network_image.dart';
import 'brand_logo.dart';

/// The desktop header: brand on the left, destinations centred, account and
/// actions on the right — with an optional search pill on a second row.
///
/// ## Why this replaced the navigation rail
///
/// The wide layout used to put an extended [NavigationRail] down the left edge.
/// It worked, but it spent ~220px of every desktop viewport on five labels that
/// never change, pushed the content panel permanently off-centre, and left the
/// search field buried inside the Explore tab where the rest of the page
/// scrolls past it. A marketplace's header is its search box; a rail cannot be
/// one.
///
/// So the chrome moved to the top, in the shape every travel site has settled
/// on: identity left, navigation centre, account right, search underneath. The
/// full viewport width goes to listings, and the search pill sits in fixed
/// chrome that no amount of scrolling can take away.
///
/// ## What it deliberately does not do
///
/// **It is not a mobile layout.** Nothing here renders below
/// `Responsive.wide` — phones and portrait tablets keep the bottom navigation
/// bar untouched, which is why there is no hamburger-drawer fallback in this
/// file. The account menu's hamburger is Airbnb's account affordance, not a
/// responsive collapse.
///
/// **It holds no state of its own.** Every destination, action and menu item is
/// supplied by [MainShell], which already owns `_guestTabIndex` /
/// `_hostTabIndex` and the gates around them. A second navigation model that
/// could disagree with the bottom bar is exactly the trap the rail avoided by
/// sharing those indices, and this keeps that property.
class DesktopTopNav extends StatelessWidget {
  const DesktopTopNav({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.accountMenu,
    this.primaryAction,
    this.trailing = const [],
    this.searchBar,
    this.onBrandTap,
    this.avatarUrl,
    this.displayName,
    this.accountHighlighted = false,
  });

  /// The tab strip. Kept to four or so: this is the top-level navigation, not
  /// a menu. Anything account-shaped belongs in [accountMenu].
  final List<DesktopNavDestination> destinations;

  /// Which destination is current, or **-1 for none**.
  ///
  /// -1 is a real state, not a bug guard: Profile is reachable from
  /// [accountMenu] but is not a destination, so while it is on screen no tab is
  /// current. [accountHighlighted] is how the header still says "you are here".
  final int selectedIndex;

  final ValueChanged<int> onDestinationSelected;

  /// The one text action beside the account button — "Log in or sign up",
  /// "Become a host" or "Switch to hosting", whichever applies.
  final DesktopTopNavAction? primaryAction;

  /// Icon-only actions (leaderboard, notification bell) between
  /// [primaryAction] and the account button.
  final List<Widget> trailing;

  /// The account menu's contents. Rendered in order; an item may ask for a
  /// divider above itself.
  final List<DesktopAccountMenuItem> accountMenu;

  /// The second row — the search bar, supplied whole by the caller.
  ///
  /// Opaque on purpose. The header is a layout: it knows a row goes here and
  /// how much space it gets, and nothing about searching. That is why
  /// `SearchPill` lives in widgets/search/ rather than in this file, where an
  /// earlier version of it started growing panels.
  ///
  /// Null on every tab but Explore — a search bar above the Earnings screen
  /// would be furniture.
  final Widget? searchBar;

  final VoidCallback? onBrandTap;

  final String? avatarUrl;
  final String? displayName;

  /// Rings the account button in the brand colour. Set while a screen behind
  /// the account menu (Profile) is the current tab — see [selectedIndex].
  final bool accountHighlighted;

  @override
  Widget build(BuildContext context) {
    // Same clamp as the bottom bar and the old rail: past ~1.1 the destination
    // labels and the pill's two-line segments start colliding, and a header is
    // the one surface a user cannot scroll to escape.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(
            bottom: BorderSide(color: AppColors.outline, width: 0.5),
          ),
        ),
        // The search row exists on Explore and nowhere else, so the header
        // changes height whenever the tab changes. Animated, because an
        // unanimated 82px snap under the cursor reads as the page jumping
        // rather than as chrome adapting. topCenter so the nav row above stays
        // put and only the pill slides out from under it.
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 74, child: _navRow(context)),
              if (searchBar != null) _searchRow(searchBar!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _Brand(onTap: onBrandTap),
          // Centred in the gap between brand and actions rather than in the
          // viewport. True centring would need the two flanks to measure the
          // same, and they never do — so it would mean either a LayoutBuilder
          // guard or a Stack that overlaps the brand just above 1000px. The
          // offset is a few dozen pixels and reads as centred; an overlapping
          // logo would not.
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // Only ever scrolls if a viewport this wide still cannot fit
                // four labels. It is an overflow guard, not a feature.
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      _NavItem(
                        destination: destinations[i],
                        selected: i == selectedIndex,
                        onTap: () => onDestinationSelected(i),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (primaryAction != null) ...[
            _HoverPill(
              onTap: primaryAction!.onTap,
              tooltip: primaryAction!.tooltip,
              child: Text(
                primaryAction!.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          for (final action in trailing) ...[
            action,
            const SizedBox(width: 4),
          ],
          const SizedBox(width: 4),
          _AccountButton(
            items: accountMenu,
            avatarUrl: avatarUrl,
            displayName: displayName,
            highlighted: accountHighlighted,
          ),
        ],
      ),
    );
  }

  Widget _searchRow(Widget bar) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 24, 16),
      child: Center(child: bar),
    );
  }
}

/// One destination in the header's tab strip.
class DesktopNavDestination {
  const DesktopNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
    this.showDot = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Unread count, rendered as a numbered badge. 0 hides it.
  final int badgeCount;

  /// A dot rather than a number, for "something is waiting" with no count
  /// (the host's pending booking requests).
  final bool showDot;
}

/// The single text action to the left of the account button.
class DesktopTopNavAction {
  const DesktopTopNavAction({
    required this.label,
    required this.onTap,
    this.tooltip,
  });

  final String label;
  final VoidCallback onTap;
  final String? tooltip;
}

/// One row in the account menu.
class DesktopAccountMenuItem {
  const DesktopAccountMenuItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.emphasized = false,
    this.dividerAbove = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  /// Bolder text, for the one item the menu exists to offer — "Log in or sign
  /// up" to a visitor.
  final bool emphasized;

  final bool dividerAbove;
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

class _Brand extends StatelessWidget {
  const _Brand({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mark = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Untinted, like every other call site: the rose IS the brand, and
        // repainting it per palette would swap the logo for the theme.
        const BrandLogo(size: 28),
        const SizedBox(width: 8),
        Text(
          'Musaafir',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );

    if (onTap == null) return mark;
    return _HoverPill(
      onTap: onTap!,
      tooltip: 'Musaafir home',
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: mark,
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final DesktopNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.destination;
    final selected = widget.selected;
    final color = selected
        ? AppColors.ink
        : (_hovered ? AppColors.ink : AppColors.inkMuted);

    Widget icon = Icon(
      selected ? d.selectedIcon : d.icon,
      size: 20,
      color: selected ? AppColors.brand : color,
    );
    if (d.badgeCount > 0) {
      icon = Badge(
        label: Text(d.badgeCount > 99 ? '99+' : '${d.badgeCount}'),
        backgroundColor: AppColors.error,
        child: icon,
      );
    } else if (d.showDot) {
      icon = Badge(backgroundColor: AppColors.error, child: icon);
    }

    return Semantics(
      button: true,
      selected: selected,
      label: d.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          // Keyboard focus has to be visible; the underline alone is a hover
          // affordance and does not read as focus.
          focusColor: AppColors.brand.withValues(alpha: 0.10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              // The rule is a bottom border rather than a sized bar so it
              // measures itself against the label — no IntrinsicWidth, no
              // hard-coded per-item width to drift from the text.
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected
                        ? AppColors.brand
                        : (_hovered ? AppColors.outline : Colors.transparent),
                    width: 2.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 8),
                  Text(
                    d.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tap target that grows a soft grey pill under the cursor.
///
/// The header's text actions and the brand share it so hover feels identical
/// across the whole bar. The 44px floor keeps every one of them a real target
/// even though the text inside is 20px tall.
class _HoverPill extends StatefulWidget {
  const _HoverPill({
    required this.child,
    required this.onTap,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final Widget child;
  final VoidCallback onTap;
  final String? tooltip;
  final EdgeInsets padding;

  @override
  State<_HoverPill> createState() => _HoverPillState();
}

class _HoverPillState extends State<_HoverPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget result = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(24),
        focusColor: AppColors.brand.withValues(alpha: 0.10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 44),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return result;
  }
}

/// Hamburger + avatar, opening the account menu.
///
/// A [PopupMenuButton] rather than a hand-rolled overlay so the menu inherits
/// dismiss-on-outside-tap, arrow-key traversal, escape-to-close and the screen
/// reader's menu semantics — all things a positioned [Overlay] would have to
/// reimplement, badly.
class _AccountButton extends StatefulWidget {
  const _AccountButton({
    required this.items,
    required this.highlighted,
    this.avatarUrl,
    this.displayName,
  });

  final List<DesktopAccountMenuItem> items;
  final bool highlighted;
  final String? avatarUrl;
  final String? displayName;

  @override
  State<_AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<_AccountButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PopupMenuButton<int>(
        tooltip: 'Account and more',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 6),
        color: AppColors.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.outline, width: 0.5),
        ),
        onSelected: (i) => widget.items[i].onTap(),
        itemBuilder: (context) => [
          for (var i = 0; i < widget.items.length; i++) ...[
            if (widget.items[i].dividerAbove) const PopupMenuDivider(),
            PopupMenuItem<int>(
              value: i,
              height: 44,
              child: Row(
                children: [
                  if (widget.items[i].icon != null) ...[
                    Icon(
                      widget.items[i].icon,
                      size: 19,
                      color: AppColors.inkMuted,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Text(
                    widget.items[i].label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: widget.items[i].emphasized
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 44,
          padding: const EdgeInsets.fromLTRB(14, 0, 5, 0),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: widget.highlighted ? AppColors.brand : AppColors.outline,
              width: widget.highlighted ? 1.4 : 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_rounded, size: 18, color: AppColors.ink),
              const SizedBox(width: 10),
              _Avatar(url: widget.avatarUrl, name: widget.displayName),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.url, this.name});

  final String? url;
  final String? name;

  @override
  Widget build(BuildContext context) {
    const size = 32.0;
    final photo = url?.trim();
    if (photo != null && photo.isNotEmpty) {
      return ClipOval(
        child: AppNetworkImage(
          url: photo,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // A broken avatar must not leave a torn image box in the chrome.
          errorWidget: _Initial(name: name, size: size),
        ),
      );
    }
    return _Initial(name: name, size: size);
  }
}

/// The avatar's fallback: the account's first letter, or a person glyph for a
/// visitor with no account at all.
class _Initial extends StatelessWidget {
  const _Initial({required this.size, this.name});

  final double size;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name?.trim() ?? '';
    final letter = trimmed.isEmpty ? null : trimmed.characters.first;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: letter == null ? AppColors.surfaceMuted : AppColors.brand,
        shape: BoxShape.circle,
      ),
      child: letter == null
          ? Icon(Icons.person, size: 19, color: AppColors.inkMuted)
          : Text(
              letter.toUpperCase(),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
    );
  }
}
