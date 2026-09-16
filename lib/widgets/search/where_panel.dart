import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/listing.dart';
import '../../models/listing_type.dart';
import '../../services/places_service.dart';
import '../../services/search/search_scope.dart';
import '../map_place_search_bar.dart' show PlaceLocateFn, PlaceSuggestFn;
import 'search_draft.dart';
import 'search_scope_picker.dart';

/// A place the app already has listings in — offered instantly, with no
/// network round trip, because these are the searches most likely to succeed.
class CitySuggestion {
  const CitySuggestion({
    required this.city,
    required this.count,
    this.noun = 'stay',
  });

  final String city;
  final int count;

  /// What the count is counting. A turf-scoped search must not offer "Dhaka —
  /// 9 stays": those nine are rooms and seats, and the search about to run
  /// will return none of them. See [citySuggestionsFrom].
  final String noun;

  String get countLabel => count == 1 ? '1 $noun' : '$count ${noun}s';
}

/// Where the panel's rows come from.
///
/// Both lookups are injected rather than reached for as singletons, following
/// [MapPlaceSearchBar] — that is what makes this panel testable without a
/// network, and the reason the typedefs already exist.
/// Known places matching a query, narrowed to the types the search is scoped
/// to — an empty list means "every type".
typedef CitySuggestFn = List<CitySuggestion> Function(
  String query,
  List<ListingType> types,
);
typedef CurrentLocationFn = Future<PlaceLocation?> Function();

/// Listings matching a query within the search's own type filter.
typedef ListingSuggestFn = List<Listing> Function(
  String query,
  List<ListingType> types,
);

/// The "Where" panel: a field, "Nearby", known cities, then Google predictions.
///
/// A near-literal port of the search sheet's location section, with its three
/// hard-won guards intact — they are not incidental, each one was a visible
/// bug:
///
/// - **A 300ms debounce with a request id.** Predictions arrive out of order,
///   and without the id an older, slower response overwrites a newer one and
///   the list shows results for a prefix of what was typed.
/// - **A programmatic-write guard.** Writing the picked name into the field
///   fires the controller listener, which recomputes suggestions and schedules
///   a fresh lookup — reopening the dropdown ~300ms after the tap that was
///   meant to close it.
/// - **An in-flight lock while resolving.** Two taps in quick succession would
///   otherwise race two `locate` calls and the loser could win.
class WherePanel extends StatefulWidget {
  const WherePanel({
    super.key,
    required this.draft,
    required this.cities,
    required this.onSubmit,
    this.suggest,
    this.locate,
    this.currentLocation,
    this.matchingListings,
    this.onOpenListing,
    this.debounce = const Duration(milliseconds: 300),
  });

  final SearchDraft draft;

  /// Known cities matching a query, from the listing cache.
  final CitySuggestFn cities;

  /// Enter in the field runs the search, the way it does in any search box.
  final VoidCallback onSubmit;

  /// Listings in the cache matching what has been typed, already narrowed to
  /// the search's types. Null in surfaces that have no listing to open.
  final ListingSuggestFn? matchingListings;

  /// Opening one is the caller's job: the panel lives in an overlay the
  /// listing screen would be pushed over.
  final ValueChanged<Listing>? onOpenListing;

  final PlaceSuggestFn? suggest;
  final PlaceLocateFn? locate;
  final CurrentLocationFn? currentLocation;
  final Duration debounce;

  @override
  State<WherePanel> createState() => _WherePanelState();
}

class _WherePanelState extends State<WherePanel> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  List<CitySuggestion> _cities = const [];

  /// Listings matching what has been typed, within the search's types.
  List<Listing> _matches = const [];

  /// Named for what is being offered, so a turf search does not head its own
  /// results "Stays".
  String get _matchLabel {
    final types = widget.draft.propertyTypes;
    if (types.length != 1) return 'Matching stays';
    return 'Matching ${types.first.title.toLowerCase()}s';
  }

  List<Listing> _matchesFor(String query) =>
      widget.matchingListings?.call(query, widget.draft.propertyTypes) ??
      const [];
  List<PlaceSuggestion> _places = const [];
  bool _searchingPlaces = false;
  String? _resolvingPlaceId;
  bool _locatingMe = false;

  Timer? _debounce;
  int _requestId = 0;
  bool _writingProgrammatically = false;

  /// Minimum characters before a Google lookup. City rows stay instant.
  static const _minCharsForPlaces = 3;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.draft.locationText);
    _controller.addListener(_onChanged);
    // The panel opened because the guest wants to type a place; landing them in
    // the field saves the second click.
    _focusNode.requestFocus();
    _cities =
        widget.cities(widget.draft.locationText, widget.draft.propertyTypes);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<List<PlaceSuggestion>> _suggest(String query) => (widget.suggest ??
      (q) => PlacesService().suggest(q, establishmentsOnly: false))(query);

  Future<PlaceLocation?> _locate(PlaceSuggestion suggestion) =>
      (widget.locate ?? (s) => PlacesService().locate(s))(suggestion);

  void _onChanged() {
    if (_writingProgrammatically) return;
    final raw = _controller.text;
    // A manual edit invalidates whatever was resolved — otherwise the search
    // runs the new name at the old coordinates.
    widget.draft.setLocationText(raw);

    _debounce?.cancel();
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      setState(() {
        // Back to the default list, NOT to nothing. An empty panel showing only
        // "Nearby" reads as broken, and this branch fires more often than it
        // looks: focusing the field round-trips the editing value through the
        // platform, which notifies the controller with the same empty text.
        _cities = widget.cities('', widget.draft.propertyTypes);
        _matches = const [];
        _places = const [];
        _searchingPlaces = false;
      });
      return;
    }

    final wantPlaces = trimmed.length >= _minCharsForPlaces;
    if (wantPlaces) {
      _debounce = Timer(widget.debounce, () => _fetchPlaces(trimmed));
    }
    setState(() {
      _cities = widget.cities(trimmed, widget.draft.propertyTypes);
      _matches = _matchesFor(trimmed);
      _searchingPlaces = wantPlaces;
      if (!wantPlaces) _places = const [];
    });
  }

  Future<void> _fetchPlaces(String query) async {
    final id = ++_requestId;
    final results = await _suggest(query);
    // Stale: something newer was typed while this was in flight.
    if (!mounted || id != _requestId) return;
    final cityNames = _cities.map((c) => c.city.toLowerCase().trim()).toSet();
    setState(() {
      _places = results
          .where((s) => !cityNames.contains(s.name.toLowerCase().trim()))
          .toList();
      _searchingPlaces = false;
    });
  }

  /// Writes [text] into the field without the listener treating it as typing.
  void _setText(String text) {
    _writingProgrammatically = true;
    _controller.text = text;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: text.length));
    _writingProgrammatically = false;
  }

  void _pickCity(CitySuggestion city) {
    _debounce?.cancel();
    _requestId++; // invalidate anything in flight
    _setText(city.city);
    // A known city searches by name, not by a ring around its geometric
    // centre — the classic text search covers the whole city.
    widget.draft.setResolvedPlace(text: city.city);
    setState(() {
      _cities = const [];
      _matches = const [];
      _places = const [];
      _searchingPlaces = false;
    });
  }

  Future<void> _pickPlace(PlaceSuggestion suggestion) async {
    if (_resolvingPlaceId != null) return;
    _debounce?.cancel();
    _requestId++;
    _setText(suggestion.name);
    setState(() => _resolvingPlaceId = suggestion.placeId);

    // locate, not resolve: the bar needs coordinates AND the place's viewport,
    // which is what lets a search cover exactly this area. resolve would
    // flatten it to a point.
    final place = await _locate(suggestion);
    if (!mounted) return;
    setState(() {
      _resolvingPlaceId = null;
      _places = const [];
      _cities = const [];
      _matches = const [];
      _searchingPlaces = false;
    });
    // A failed resolve is not an error: the commit geocodes the text instead.
    widget.draft.setResolvedPlace(
      text: suggestion.name,
      latitude: place?.latitude,
      longitude: place?.longitude,
      bounds: place?.bounds,
    );
  }

  Future<void> _useCurrentLocation() async {
    final lookup = widget.currentLocation;
    if (lookup == null) return;
    setState(() => _locatingMe = true);
    final place = await lookup();
    if (!mounted) return;
    setState(() => _locatingMe = false);
    if (place == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't get your location — check permission."),
        ),
      );
      return;
    }
    final label = place.name.isEmpty ? 'Current location' : place.name;
    _setText(label);
    // "Near me" is a point-and-radius search, not an area, so no box.
    widget.draft.setResolvedPlace(
      text: label,
      latitude: place.latitude,
      longitude: place.longitude,
    );
    setState(() {
      _cities = const [];
      _matches = const [];
      _places = const [];
    });
  }

  /// Writes the scope through [applyScope], which is also what drops a
  /// purpose that cannot coexist with turf. Rebuilds locally because the
  /// panel reads `draft.propertyTypes` directly — the draft notifies, but this
  /// widget is not inside its `ListenableBuilder`.
  void _onScope(SearchScope scope) {
    final next = applyScope(
      scope,
      types: widget.draft.propertyTypes,
      purpose: widget.draft.purpose,
      landmark: widget.draft.landmark,
    );
    setState(() {
      widget.draft.edit(() {
        widget.draft.propertyTypes = next.types;
        widget.draft.purpose = next.purpose;
        widget.draft.landmark = next.landmark;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => widget.onSubmit(),
            decoration: InputDecoration(
              hintText: 'Area, address or place — e.g. Dakshinkhan',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear',
                      onPressed: () {
                        _controller.clear();
                        _focusNode.requestFocus();
                      },
                    ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Above the suggestions, not below them: it changes what the rows
          // underneath are *for*, and a control that reframes a list has to be
          // read before the list.
          SearchScopePicker(
            scope: scopeOf(widget.draft.propertyTypes),
            onSelected: _onScope,
          ),
          const SizedBox(height: 4),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.currentLocation != null)
                    _SuggestionRow(
                      icon: Icons.near_me_outlined,
                      iconColor: AppColors.blue,
                      title: 'Nearby',
                      subtitle: 'Find what’s around you',
                      busy: _locatingMe,
                      onTap: _locatingMe ? null : _useCurrentLocation,
                    ),
                  // The listings themselves, first. A guest who has already
                  // said Turf and typed an area is looking for grounds, not
                  // for which "Uttara" they meant — offering only places makes
                  // them commit to another round trip before they see one.
                  if (_matches.isNotEmpty) ...[
                    _SectionLabel(label: _matchLabel),
                    for (final listing in _matches)
                      _SuggestionRow(
                        icon: Icons.place_rounded,
                        iconColor: AppColors.brand,
                        title: listing.title,
                        subtitle: listing.address,
                        onTap: () => widget.onOpenListing?.call(listing),
                      ),
                  ],
                  // Scoping to a type the app has none of empties this list,
                  // and a panel that answers a typed query with nothing reads
                  // as broken rather than as an answer. Say which it is.
                  if (_matches.isEmpty &&
                      _cities.isEmpty &&
                      widget.draft.propertyTypes.length == 1) ...[
                    _SectionLabel(
                      label: 'No '
                          '${widget.draft.propertyTypes.first.title.toLowerCase()}'
                          's listed yet — try Anything',
                    ),
                  ],
                  if (_cities.isNotEmpty) ...[
                    _SectionLabel(
                      label: _controller.text.trim().isEmpty
                          ? 'Suggested destinations'
                          : 'Places with stays',
                    ),
                    for (final city in _cities)
                      _SuggestionRow(
                        icon: Icons.location_city_outlined,
                        iconColor: AppColors.brand,
                        title: city.city,
                        subtitle: city.countLabel,
                        onTap: () => _pickCity(city),
                      ),
                  ],
                  if (_searchingPlaces && _places.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  if (_places.isNotEmpty) ...[
                    // Not "Search results": actual listings sit above these
                    // now, and two headings where the lower one claims the
                    // results reads as though the places are the answer.
                    const _SectionLabel(label: 'Places'),
                    for (final place in _places)
                      _SuggestionRow(
                        icon: Icons.place_outlined,
                        iconColor: AppColors.inkMuted,
                        title: place.name,
                        subtitle: place.label,
                        busy: _resolvingPlaceId == place.placeId,
                        onTap: _resolvingPlaceId != null
                            ? null
                            : () => _pickPlace(place),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.inkMuted,
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor:
          onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 21, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (busy) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
