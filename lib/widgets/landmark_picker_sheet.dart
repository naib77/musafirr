import 'package:flutter/material.dart';

import '../models/landmark.dart';
import '../repositories/musafir_repository.dart';

/// Opens a bottom sheet to pick a landmark (hospital / exam center / …) of a
/// given [type], and returns the chosen [Landmark] (or null if dismissed).
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
  List<Landmark> _results = [];
  bool _loading = true;
  // Guards against out-of-order responses when the user types quickly.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final id = ++_requestId;
    setState(() => _loading = true);
    final results = await widget.repository
        .searchLandmarks(query: query, type: widget.type);
    if (!mounted || id != _requestId) return;
    setState(() {
      _results = results;
      _loading = false;
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
                    onChanged: _search,
                    decoration: InputDecoration(
                      hintText: 'Search by name or area…',
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            'No matches found',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final l = _results[i];
                            return ListTile(
                              leading: const Icon(Icons.place_rounded),
                              title: Text(l.name),
                              subtitle: l.locationLabel.isEmpty
                                  ? null
                                  : Text(l.locationLabel),
                              onTap: () => Navigator.pop(context, l),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
