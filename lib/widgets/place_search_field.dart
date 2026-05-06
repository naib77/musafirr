import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import '../services/location_service.dart';

class PlaceSearchResult {
  const PlaceSearchResult({
    required this.query,
    required this.latitude,
    required this.longitude,
  });

  final String query;
  final double latitude;
  final double longitude;
}

class PlaceSearchField extends StatefulWidget {
  const PlaceSearchField({
    super.key,
    required this.onPlaceSelected,
    this.initialValue,
    this.hintText = 'Search for a place...',
  });

  final void Function(PlaceSearchResult result) onPlaceSelected;
  final String? initialValue;
  final String hintText;

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _locationService = LocationService();

  bool _isSearching = false;
  List<Location> _results = [];
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        setState(() => _showResults = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) {
      setState(() {
        _results = [];
        _showResults = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showResults = true;
    });

    final locations = await _locationService.searchAddress(query);

    if (mounted) {
      setState(() {
        _isSearching = false;
        _results = locations;
      });
    }
  }

  void _selectResult(Location location) {
    final query = _controller.text;
    _focusNode.unfocus();
    setState(() {
      _showResults = false;
      _results = [];
    });

    widget.onPlaceSelected(PlaceSearchResult(
      query: query,
      latitude: location.latitude,
      longitude: location.longitude,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: widget.hintText,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isSearching
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
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _results = [];
                            _showResults = false;
                          });
                        },
                      )
                    : null,
            border: const OutlineInputBorder(),
          ),
          onChanged: _search,
        ),
        if (_showResults && _results.isNotEmpty)
          Material(
            elevation: 4,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final location = _results[index];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(_controller.text),
                  subtitle: Text(
                    '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}',
                  ),
                  onTap: () => _selectResult(location),
                );
              },
            ),
          ),
      ],
    );
  }
}
