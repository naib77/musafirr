import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The mobile search sheet's pinned footer: Clear all on the left, Search on
/// the right.
///
/// The Search button used to be the last child of the sheet's
/// `SingleChildScrollView`, so it scrolled away — on a short phone with the
/// keyboard up, the primary action of the whole sheet was off screen and the
/// guest had to scroll past every filter to reach it. It is pinned now, which
/// is also what makes room for Clear all: a reset is only safe to offer where
/// the guest can see what it did.
///
/// Extracted rather than inlined because `_SearchSheet` is private to
/// `explore_screen.dart` and nothing pumps that screen in a test — a footer
/// left in there could not be asserted on at all. It is also the first piece of
/// that sheet shaped for reuse when the sheet is eventually rebuilt out of the
/// desktop panels (see CLAUDE.md on the two copies of these controls).
class SearchSheetFooter extends StatelessWidget {
  const SearchSheetFooter({
    super.key,
    required this.onClearAll,
    required this.onSearch,
    this.busy = false,
  });

  /// Resets the sheet's own draft — not the committed search. Nothing is
  /// applied until Search, so a guest who clears and then closes the sheet
  /// keeps the results they already had.
  ///
  /// Deliberately always enabled, even on a pristine form: the alternative is a
  /// second definition of "is anything set" living beside `hasActiveFilters`
  /// and `SearchDraft.hasAnyInput`, and those drifting apart is a worse bug
  /// than a no-op tap on a form with nothing in it.
  final VoidCallback onClearAll;

  /// Null while a place is being resolved, which is what disables the button.
  final VoidCallback? onSearch;

  /// Swaps the icon for a spinner and says what it is waiting on.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        // A hairline, not a shadow: the sheet already floats, and a second
        // shadow inside it reads as two stacked surfaces.
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            // Expanded, not Flexible: a loose Flexible sizes to the label and
            // leaves the slack *after* the row's last child, which parked the
            // Search button in the middle of the bar instead of flush right.
            // Expanded absorbs the slack here, so Clear all stays left, Search
            // stays right, and a large text scale shrinks this label (it
            // ellipsizes) rather than overflowing — the Search button is the
            // primary action and must stay whole.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onClearAll,
                  style: TextButton.styleFrom(
                    // 48 tall, and enough horizontal padding to clear 44px of
                    // touch target on the shortest label.
                    minimumSize: const Size(64, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    foregroundColor: AppColors.ink,
                  ),
                  child: const Text(
                    'Clear all',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: onSearch,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: busy
                    ? const [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('Finding place…'),
                      ]
                    : const [
                        Icon(Icons.search, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Search',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
