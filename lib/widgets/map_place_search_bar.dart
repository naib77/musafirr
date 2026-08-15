import 'dart:async';

import 'package:flutter/material.dart';

import '../services/places_service.dart';

typedef PlaceSuggestFn = Future<List<PlaceSuggestion>> Function(String query);
typedef PlaceLocateFn = Future<PlaceLocation?> Function(
    PlaceSuggestion suggestion);

/// Type-ahead place search that floats over a map: type a few letters, tap a
/// prediction, and the map moves there — the way Google Maps itself behaves.
/// Reporting the pick is all this widget does; the caller owns the camera.
///
/// It searches through Google Places (the `places-search` edge function), not
/// the `geocoding` package. That package ships Android and iOS implementations
/// only, so every search from a browser threw `MissingPluginException` into a
/// swallowed catch and the field just sat there — which is how this widget came
/// to exist. Anything that searches for a place from web code must go through a
/// server-side path like this one.
class MapPlaceSearchBar extends StatefulWidget {
  const MapPlaceSearchBar({
    super.key,
    required this.onPlacePicked,
    this.hintText = 'Search for a place or address…',
    this.suggest,
    this.locate,
    this.debounce = const Duration(milliseconds: 300),
  });

  final ValueChanged<PlaceLocation> onPlacePicked;
  final String hintText;

  /// Injected in tests; production uses [PlacesService].
  final PlaceSuggestFn? suggest;
  final PlaceLocateFn? locate;

  /// Type-ahead fires this long after the last keystroke, so a five-letter
  /// query costs one request instead of five.
  final Duration debounce;

  /// Predictions start at this many characters — fewer matches everything in
  /// Dhaka and tells the host nothing.
  static const int minChars = 3;

  static const Key fieldKey = ValueKey('map-place-search-field');

  @override
  State<MapPlaceSearchBar> createState() => _MapPlaceSearchBarState();
}

class _MapPlaceSearchBarState extends State<MapPlaceSearchBar> {
  final _controller = TextEditingController();
  final _places = PlacesService();

  Timer? _debounce;

  /// Guards against out-of-order responses when the host types quickly.
  int _requestId = 0;

  List<PlaceSuggestion> _suggestions = [];
  bool _searching = false;
  bool _searched = false;
  String? _resolvingId;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  PlaceSuggestFn get _suggest =>
      widget.suggest ??
      ((query) => _places.suggest(query, establishmentsOnly: false));

  PlaceLocateFn get _locate => widget.locate ?? _places.locate;

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < MapPlaceSearchBar.minChars) {
      _requestId++;
      setState(() {
        _suggestions = [];
        _searching = false;
        _searched = false;
      });
      return;
    }
    _debounce = Timer(widget.debounce, () => _search(query));
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    setState(() => _searching = true);

    final results = await _suggest(query.trim());
    if (!mounted || id != _requestId) return;

    setState(() {
      _suggestions = results;
      _searching = false;
      _searched = true;
    });
  }

  Future<void> _pick(PlaceSuggestion suggestion) async {
    if (_resolvingId != null) return;
    setState(() => _resolvingId = suggestion.placeId);

    final place = await _locate(suggestion);
    if (!mounted) return;

    if (place == null) {
      setState(() => _resolvingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t load this place — try again')),
      );
      return;
    }

    // The field keeps the name of the place the map is now showing, so it is
    // obvious what was searched for.
    _controller.text = place.name;
    setState(() {
      _resolvingId = null;
      _suggestions = [];
      _searched = false;
    });
    FocusScope.of(context).unfocus();
    widget.onPlacePicked(place);
  }

  void _clear() {
    _debounce?.cancel();
    _requestId++;
    _controller.clear();
    setState(() {
      _suggestions = [];
      _searching = false;
      _searched = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surface,
          child: TextField(
            key: MapPlaceSearchBar.fieldKey,
            controller: _controller,
            textInputAction: TextInputAction.search,
            onChanged: _onQueryChanged,
            onSubmitted: (q) {
              _debounce?.cancel();
              if (q.trim().length >= MapPlaceSearchBar.minChars) _search(q);
            },
            decoration: InputDecoration(
              hintText: widget.hintText,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clear,
                        )
                      : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: theme.colorScheme.surface,
            ),
          ),
        ),
        if (_suggestions.isNotEmpty || (_searched && !_searching))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                // Tall enough for a handful of predictions, short enough that
                // the map is still visible behind them.
                constraints: const BoxConstraints(maxHeight: 260),
                child: _suggestions.isEmpty
                    ? const ListTile(
                        leading: Icon(Icons.search_off_rounded),
                        title: Text('No places found'),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, i) {
                          final s = _suggestions[i];
                          final busy = _resolvingId == s.placeId;
                          return ListTile(
                            leading: busy
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.location_on_outlined),
                            title: Text(s.name, maxLines: 1),
                            subtitle: s.label.isEmpty
                                ? null
                                : Text(s.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                            onTap: () => _pick(s),
                          );
                        },
                      ),
              ),
            ),
          ),
      ],
    );
  }
}
