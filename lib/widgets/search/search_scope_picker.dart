import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../services/search/search_scope.dart';

/// "Anything / Turf" — the one-tap cut at the top of Where.
///
/// Turf reached the app as a `ListingType`, which put it in the Filters panel
/// beside Seat and Room. That is correct as a model and wrong as a question:
/// finding a ground is four steps (open Filters, tick Turf, close, then type
/// the area), while Medical — the other thing a guest comes here specifically
/// to find — is one visible tap. A ground is not an overflow refinement of a
/// stay search; it is a different search.
///
/// So this sits under the Where field, above the suggestions, in both
/// surfaces. It writes a `ListingType` like the Filters chips do — see
/// [applyScope] for the one rule that has to travel with it.
///
/// Stateless over a value and a callback, the shape `GuestPartyFields` already
/// uses, because the desktop panel holds a `SearchDraft` and the mobile sheet
/// holds plain `setState` and both have to render the same control.
class SearchScopePicker extends StatelessWidget {
  const SearchScopePicker({
    super.key,
    required this.scope,
    required this.onSelected,
  });

  final SearchScope scope;
  final ValueChanged<SearchScope> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ScopePill(
          icon: Icons.apps_rounded,
          label: 'Anything',
          selected: scope == SearchScope.any,
          onTap: () => onSelected(SearchScope.any),
        ),
        _ScopePill(
          icon: Icons.sports_soccer_rounded,
          label: 'Turf',
          selected: scope == SearchScope.turf,
          onTap: () => onSelected(SearchScope.turf),
        ),
      ],
    );
  }
}

class _ScopePill extends StatelessWidget {
  const _ScopePill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // A solid brand fill when selected, label and icon in `surface`. Same
    // choice the chip theme makes, and for the same reason: a tint at low
    // alpha over surfaceMuted is invisible in a palette whose brand is nearly
    // black, and it leaves no second cue when the border is none.
    final fg = selected ? AppColors.surface : AppColors.ink;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.brand : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              // Or the Wrap's full line width turns every pill into its own
              // full-width bar — the bug `PurposePicker` shipped once.
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
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
