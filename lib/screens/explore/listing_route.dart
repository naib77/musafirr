import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../state/messaging_state.dart';
import 'listing_detail_screen.dart';

/// `/listing/<id>` — the shareable address of one stay.
///
/// [ListingDetailScreen] takes a fully-built [Listing], which is right for a
/// tap on a card (the object is already in hand, and re-fetching it would put
/// a spinner in front of content the visitor can already see). A pasted link
/// has only an id, so this stands in front and resolves one into the other.
///
/// Pass [listing] whenever the caller has it; the fetch is then skipped
/// entirely and this is a transparent wrapper.
class ListingRoute extends StatefulWidget {
  const ListingRoute({
    super.key,
    required this.listingId,
    required this.repository,
    required this.authState,
    required this.favoritesState,
    this.listing,
    this.messagingState,
  });

  final String listingId;
  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;

  /// The already-loaded listing, when the caller navigated from a card.
  final Listing? listing;

  final MessagingStateNotifier? messagingState;

  @override
  State<ListingRoute> createState() => _ListingRouteState();
}

class _ListingRouteState extends State<ListingRoute> {
  Listing? _listing;
  bool _loading = false;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _listing = widget.listing;
    if (_listing == null) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final listing = await widget.repository.fetchListingById(widget.listingId);
    if (!mounted) return;
    setState(() {
      _listing = listing;
      _notFound = listing == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final listing = _listing;
    if (listing != null) {
      return ListingDetailScreen(
        listing: listing,
        repository: widget.repository,
        authState: widget.authState,
        favoritesState: widget.favoritesState,
        messagingState: widget.messagingState,
      );
    }

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Not found, or hidden. Deliberately one message for both: the SELECT
    // policy shows only active listings, so "this id does not exist" and "the
    // host took it down" are indistinguishable from here — and telling a
    // stranger which it was would leak whether an id is real.
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'This place is no longer listed',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'It may have been removed, or the link may be wrong.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Deep-linked cold starts get the shell pushed underneath (see
              // onGenerateInitialRoutes), so there is always somewhere to go.
              if (Navigator.of(context).canPop())
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Browse other places'),
                )
              else
                FilledButton(
                  onPressed: _notFound ? null : _load,
                  child: const Text('Try again'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
