import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/landmark.dart';
import '../../models/listing_purpose.dart';
import '../../models/listing_type.dart';
import '../purpose_scroll.dart';
import 'search_draft.dart';

/// Asks for a landmark of [type], titled for [purpose]. Returns null when the
/// guest backs out.
typedef LandmarkPickFn = Future<Landmark?> Function(
  BuildContext context, {
  required String type,
  required String title,
});

/// Everything that narrows a search but has no home in Where / When / Who.
///
/// Property type and purpose used to sit in the middle of the full-screen
/// sheet. They do not belong in any of the three segments — a stay's *type* is
/// not a place, a date or a party size — so they get their own control beside
/// the bar, which is also where Airbnb puts its own overflow.
///
/// Price and amenities exist in `SearchFilters` and still have no UI anywhere.
/// This panel is where they would land.
class FiltersPanel extends StatelessWidget {
  const FiltersPanel({
    super.key,
    required this.draft,
    required this.onPickLandmark,
  });

  final SearchDraft draft;

  /// Opening the landmark picker is the caller's job because it is a
  /// **route-level modal sheet**: presenting it from inside this panel would
  /// stack a bottom sheet on top of a popover. The bar closes the popover
  /// first, awaits the pick, then reopens — see `SearchPill`.
  final LandmarkPickFn onPickLandmark;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Heading('Type of place'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TypeChip(
                    label: 'Any',
                    selected: draft.propertyTypes.isEmpty,
                    onTap: () => draft.edit(draft.propertyTypes.clear),
                  ),
                  for (final type in ListingType.values)
                    _TypeChip(
                      label: type.title,
                      selected: draft.propertyTypes.contains(type),
                      onTap: () => draft.edit(() {
                        if (!draft.propertyTypes.remove(type)) {
                          draft.propertyTypes.add(type);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              const _Heading('What the stay is for'),
              const SizedBox(height: 4),
              Text(
                'Ranks stays by how close they are to the place you name.',
                style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 10),
              PurposeScroll(
                selected: draft.purpose,
                padding: EdgeInsets.zero,
                onSelected: (purpose) => _onPurpose(context, purpose),
              ),
              if (draft.landmark != null) ...[
                const SizedBox(height: 12),
                _LandmarkRow(
                  landmark: draft.landmark!,
                  // Dropping the landmark leaves the purpose in place: it still
                  // applies as a plain tag filter without an anchor.
                  onClear: () => draft.edit(() => draft.landmark = null),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onPurpose(BuildContext context, ListingPurpose? purpose) async {
    if (purpose == null) {
      draft.edit(() {
        draft.purpose = null;
        draft.landmark = null;
      });
      return;
    }
    final type = purpose.landmarkType;
    if (type == null) {
      draft.edit(() {
        draft.purpose = purpose;
        draft.landmark = null;
      });
      return;
    }
    final chosen = await onPickLandmark(
      context,
      type: type,
      title: switch (purpose) {
        ListingPurpose.medical => 'Choose a hospital',
        ListingPurpose.exam => 'Choose an exam center',
        ListingPurpose.tourism => 'Choose an attraction',
        ListingPurpose.business => 'Choose a business hub',
        ListingPurpose.student => 'Choose a university',
        ListingPurpose.general => '',
      },
    );
    // Backed out — leave the previous selection exactly as it was rather than
    // half-applying a purpose whose anchor was never chosen.
    if (chosen == null) return;
    draft.edit(() {
      draft.purpose = purpose;
      draft.landmark = chosen;
      // The landmark anchors the search: it becomes the Where text and the
      // proximity centre, and a fixed ring replaces any place box.
      draft.locationText = chosen.name;
      draft.latitude = chosen.latitude;
      draft.longitude = chosen.longitude;
      draft.bounds = null;
    });
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      side: BorderSide(
        color: selected ? AppColors.brand : AppColors.outline,
      ),
      selectedColor: AppColors.brand.withValues(alpha: 0.10),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: AppColors.ink,
      ),
    );
  }
}

class _LandmarkRow extends StatelessWidget {
  const _LandmarkRow({required this.landmark, required this.onClear});

  final Landmark landmark;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.place_outlined, size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Near ${landmark.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: AppColors.ink),
            ),
          ),
          IconButton(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 17),
            tooltip: 'Remove landmark',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
