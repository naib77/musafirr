import 'dart:async';

import 'package:flutter/material.dart';

import '../models/landmark.dart';
import '../repositories/musafir_repository.dart';
import '../services/places_service.dart';

/// Opens a bottom sheet to pick a landmark (hospital / exam center / …) of a
/// given [type], and returns the chosen [Landmark] (or null if dismissed).
///
/// Results combine the curated `landmarks` table with live Google Places
/// matches, so any place a guest can find on Google Maps ("lubana hospital")
/// can anchor the search — not just seeded rows.
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
  List<Landmark> _placeResults = [];
  bool _loading = true;
  bool _searchingPlaces = false;
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
      const Duration(milliseconds: 350),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    final q = query.trim();
    // Google search only for real queries — the empty sheet browses seeds.
    final wantPlaces = q.length >= 3;
    setState(() {
      _loading = _seedResults.isEmpty && _placeResults.isEmpty;
      _searchingPlaces = wantPlaces;
    });

    final seedFuture =
        widget.repository.searchLandmarks(query: q, type: widget.type);
    final placesFuture = wantPlaces
        ? _places.searchPlaces(q, type: widget.type)
        : Future.value(const <Landmark>[]);

    final seeds = await seedFuture;
    if (!mounted || id != _requestId) return;
    setState(() {
      _seedResults = seeds;
      _loading = false;
    });

    final places = await placesFuture;
    if (!mounted || id != _requestId) return;
    // Drop Google entries that duplicate a curated landmark by name.
    final seedNames = seeds.map((l) => l.name.toLowerCase().trim()).toSet();
    setState(() {
      _placeResults = places
          .where((p) => !seedNames.contains(p.name.toLowerCase().trim()))
          .toList();
      _searchingPlaces = false;
    });
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
                      hintText: 'Search any place by name…',
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

    final empty = _seedResults.isEmpty && _placeResults.isEmpty;
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
    // Google Places matches (kept visually distinct via icon + section header).
    final rows = <Widget>[
      for (final l in _seedResults) _resultTile(l, icon: Icons.place_rounded),
      if (_placeResults.isNotEmpty || _searchingPlaces)
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
      for (final l in _placeResults)
        _resultTile(l, icon: Icons.travel_explore_rounded),
    ];

    return ListView(children: rows);
  }

  Widget _resultTile(Landmark l, {required IconData icon}) {
    return ListTile(
      leading: Icon(icon),
      title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: l.locationLabel.isEmpty
          ? null
          : Text(l.locationLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.pop(context, l),
    );
  }
}
