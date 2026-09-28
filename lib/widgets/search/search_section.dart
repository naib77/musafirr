import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// One folded step of the mobile search sheet — Where, When or Who.
///
/// ## Why the sheet folds at all
///
/// Everything used to be open at once: a text field, a suggestion list, a mode
/// toggle, two date cards, two time cards and four guest steppers, stacked down
/// one scroll. On a phone that is several screens of controls with no sense of
/// where you are in the task, and the thing you most often want to change is
/// wherever you last left it.
///
/// Folded, the sheet is three short rows that each say what they currently hold
/// — "Where / Uttara", "When / 12 – 15 Sep" — and exactly one of them is open.
/// The summary is the point: a collapsed row is not a hidden control, it is a
/// statement of the current answer that you tap to change.
///
/// ## Only one open at a time
///
/// The parent owns which one that is, not this widget. Two open sections would
/// put the calendar and the guest steppers on screen together and undo the
/// whole thing, and a section that tracked its own expansion could not enforce
/// that — the same reason `MainShell` owns the selected tab rather than the
/// header (see CLAUDE.md).
class SearchSection extends StatelessWidget {
  const SearchSection({
    super.key,
    required this.label,
    required this.summary,
    required this.placeholder,
    required this.expanded,
    required this.onTap,
    required this.child,
  });

  /// The quiet left-hand word: "Where", "When", "Who".
  final String label;

  /// What this step currently holds, or null when nothing has been chosen.
  final String? summary;

  /// Shown in place of [summary] when there is nothing yet. Reads as an
  /// invitation ("Add dates") rather than as a value.
  final String placeholder;

  final bool expanded;

  /// Asks the parent to open this section. Never called while [expanded] —
  /// tapping the heading of the open section would collapse the sheet into
  /// nothing open at all, which is a state with no way back except another tap.
  final VoidCallback onTap;

  /// The section's controls. Built only while open, so a collapsed When is not
  /// laying out a month grid nobody can see.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
        boxShadow: [
          BoxShadow(
            // The open card lifts; the closed ones stay flat, so the eye lands
            // on the step being answered without any colour change.
            color: Colors.black.withValues(alpha: expanded ? 0.08 : 0.03),
            blurRadius: expanded ? 18 : 6,
            offset: Offset(0, expanded ? 6 : 2),
          ),
        ],
      ),
      // Animating the height is what makes this read as one sheet rearranging
      // rather than as two different sheets.
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: expanded ? _expanded(context) : _collapsed(context),
      ),
    );
  }

  Widget _collapsed(BuildContext context) {
    return Semantics(
      button: true,
      // The row reads as one thing to a screen reader: what this step is, and
      // what it currently says. Without this the label and the value are two
      // unrelated announcements.
      label: '$label, ${summary ?? placeholder}. Tap to change.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 14, color: AppColors.inkMuted),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  summary ?? placeholder,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    // An unanswered step is muted, so a glance down the three
                    // rows shows what is still open without reading them.
                    color: summary == null ? AppColors.inkMuted : AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expanded(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // The question form, as the reference does it: the open card is
            // asking, the closed ones are reporting.
            '$label?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
