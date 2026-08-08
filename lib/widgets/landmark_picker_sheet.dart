import 'dart:async';

import 'package:flutter/material.dart';

import '../models/landmark.dart';
import '../repositories/musafir_repository.dart';
import '../services/places_service.dart';

/// Opens a bottom sheet to pick a landmark (hospital / exam center / …) of a
/// given [type], and returns the chosen [Landmark] (or null if dismissed).
///
/// Results combine the curated `landmarks` table with Google-Maps-style
/// type-ahead: three letters ("lub…") already suggest matching places
/// country-wide, so any place findable on Google Maps can anchor the search.
Future<Landmark?> showLandmarkPicker(
  BuildContext context, {
  required MusafirRepository repository,
  required String type,
  required String title,
}) {
  return showModalBottomSheet<Landmark>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LandmarkPickerSheet(
      repository: repository,
      type: type,
      title: title,
    ),
  );
}

class _LandmarkPickerSheet extends StatefulWidget {
  const _LandmarkPickerSheet({
    required this.repository,
    required this.type,
    required this.title,
  });

  final MusafirRepository repository;
  final String type;
  final String title;

  @override
  State<_LandmarkPickerSheet> createState() => _LandmarkPickerSheetState();
}

class _LandmarkPickerSheetState extends State<_LandmarkPickerSheet> {
  final _controller = TextEditingController();
  final _places = PlacesService();

  List<Landmark> _seedResults = [];
  List<PlaceSuggestion> _suggestions = [];
  bool _loading = true;
  bool _searchingPlaces = false;

  /// place_id being resolved to coordinates after a tap (shows a spinner on
  /// that tile and ignores further taps until it settles).
  String? _resolvingId;
  Timer? _debounce;
  // Guards against out-of-order responses when the user types quickly.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    final q = query.trim();
    // Type-ahead kicks in from 3 letters — the empty sheet browses seeds.
    final wantPlaces = q.length >= 3;
    setState(() {
      _loading = _seedResults.isEmpty && _suggestions.isEmpty;
      _searchingPlaces = wantPlaces;
      if (!wantPlaces) _suggestions = [];
    });

    final seedFuture =
        widget.repository.searchLandmarks(query: q, type: widget.type);
    final placesFuture = wantPlaces
        ? _places.suggest(q)
        : Future.value(const <PlaceSuggestion>[]);

    final seeds = await seedFuture;
    if (!mounted || id != _requestId) return;
    setState(() {
      _seedResults = seeds;
      _loading = false;
    });

    final suggestions = await placesFuture;
    if (!mounted || id != _requestId) return;
    // Drop Google entries that duplicate a curated landmark by name.
    final seedNames = seeds.map((l) => l.name.toLowerCase().trim()).toSet();
    setState(() {
      _suggestions = suggestions
          .where((s) => !seedNames.contains(s.name.toLowerCase().trim()))
          .toList();
      _searchingPlaces = false;
    });
  }

  Future<void> _pickSuggestion(PlaceSuggestion s) async {
    if (_resolvingId != null) return;
    setState(() => _resolvingId = s.placeId);
    final landmark = await _places.resolve(s, type: widget.type);
    if (!mounted) return;
    if (landmark == null) {
      setState(() => _resolvingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn\'t load this place — try again')),
      );
      return;
    }
    Navigator.pop(context, landmark);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    autofocus: false,
                    onChanged: _onQueryChanged,
                    decoration: InputDecoration(
                      hintText: 'Type a place name — 3 letters is enough…',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildResults(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final empty = _seedResults.isEmpty && _suggestions.isEmpty;
    if (empty && _searchingPlaces) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'Searching maps…',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (empty) {
      return Center(
        child: Text(
          'No matches found',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    // One flat list: curated landmarks first, then a labeled section of live
    // Google suggestions (kept visually distinct via icon + section header).
    final rows = <Widget>[
      for (final l in _seedResults)
        ListTile(
          leading: const Icon(Icons.place_rounded),
          title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: l.locationLabel.isEmpty
              ? null
              : Text(l.locationLabel,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.pop(context, l),
        ),
      if (_suggestions.isNotEmpty || _searchingPlaces)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Text(
                'FROM MAP SEARCH',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_searchingPlaces) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ],
            ],
          ),
        ),
      for (final s in _suggestions)
        ListTile(
          leading: const Icon(Icons.travel_explore_rounded),
          title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: s.label.isEmpty
              ? null
              : Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: _resolvingId == s.placeId
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          enabled: _resolvingId == null || _resolvingId == s.placeId,
          onTap: () => _pickSuggestion(s),
        ),
    ];

    return ListView(children: rows);
  }
}
