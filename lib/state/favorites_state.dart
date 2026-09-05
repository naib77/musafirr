import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavoritesStateNotifier extends ChangeNotifier with SafeNotifier {
  final Set<String> _favoriteIds = {};
  // Listings with an in-flight toggle request, to drop overlapping rapid taps.
  final Set<String> _togglingIds = {};
  String? _userId;
  bool _isLoading = false;

  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);
  int get count => _favoriteIds.length;
  bool get isLoading => _isLoading;

  SupabaseClient get _client => Supabase.instance.client;

  bool isFavorite(String listingId) {
    return _favoriteIds.contains(listingId);
  }

  /// Initialize favorites for the current user
  Future<void> initializeForUser(String userId) async {
    if (_userId == userId && _favoriteIds.isNotEmpty) return;

    _userId = userId;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _client
          .from('favorites')
          .select('listing_id')
          .eq('user_id', userId);

      _favoriteIds.clear();
      for (final row in response as List) {
        _favoriteIds.add(row['listing_id'] as String);
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Asks for a login when a signed-out visitor taps the heart.
  ///
  /// Wired once in `app.dart` rather than at the five heart tap sites (two on
  /// Explore, the category rail, the detail overlay, Wishlists) — several of
  /// them live in stateless card widgets that are handed a listing and a
  /// callback and have no business knowing about auth. Set to null in tests.
  Future<void> Function()? onSignInRequired;

  /// Toggle favorite status for a listing
  Future<void> toggleFavorite(String listingId) async {
    if (_userId == null) {
      // Used to be a debugPrint and nothing else, which made the heart a dead
      // pixel for a signed-out visitor: no fill, no message, no way to find
      // out why. Unreachable while the app was behind a login wall; the first
      // thing anyone taps now that it isn't.
      await onSignInRequired?.call();
      // Set by app.dart's auth listener calling initializeForUser as soon as
      // the session lands, so a visitor who signs in here gets the tap they
      // originally made rather than having to tap again. Still null means they
      // backed out.
      if (_userId == null) return;
    }

    // Drop rapid repeat taps while a request for this listing is in flight —
    // overlapping insert/delete can otherwise land out of order and leave the
    // UI and database disagreeing.
    if (_togglingIds.contains(listingId)) return;
    _togglingIds.add(listingId);

    final wasFavorite = _favoriteIds.contains(listingId);

    // Optimistic update
    if (wasFavorite) {
      _favoriteIds.remove(listingId);
    } else {
      _favoriteIds.add(listingId);
    }
    notifyListeners();

    try {
      if (wasFavorite) {
        await _client
            .from('favorites')
            .delete()
            .eq('user_id', _userId!)
            .eq('listing_id', listingId);
      } else {
        await _client.from('favorites').insert({
          'user_id': _userId,
          'listing_id': listingId,
        });
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      // Revert on error
      if (wasFavorite) {
        _favoriteIds.add(listingId);
      } else {
        _favoriteIds.remove(listingId);
      }
      notifyListeners();
    } finally {
      _togglingIds.remove(listingId);
    }
  }

  void addFavorite(String listingId) {
    if (!_favoriteIds.contains(listingId)) {
      _favoriteIds.add(listingId);
      notifyListeners();
      _persistAdd(listingId);
    }
  }

  void removeFavorite(String listingId) {
    if (_favoriteIds.contains(listingId)) {
      _favoriteIds.remove(listingId);
      notifyListeners();
      _persistRemove(listingId);
    }
  }

  Future<void> _persistAdd(String listingId) async {
    if (_userId == null) return;
    try {
      await _client.from('favorites').insert({
        'user_id': _userId,
        'listing_id': listingId,
      });
    } catch (e) {
      debugPrint('Error persisting favorite add: $e');
    }
  }

  Future<void> _persistRemove(String listingId) async {
    if (_userId == null) return;
    try {
      await _client
          .from('favorites')
          .delete()
          .eq('user_id', _userId!)
          .eq('listing_id', listingId);
    } catch (e) {
      debugPrint('Error persisting favorite remove: $e');
    }
  }

  void clearAll() {
    _favoriteIds.clear();
    _userId = null;
    notifyListeners();
  }

  // Bulk operations (local only, for compatibility)
  void addAll(Iterable<String> ids) {
    _favoriteIds.addAll(ids);
    notifyListeners();
  }

  void removeAll(Iterable<String> ids) {
    _favoriteIds.removeAll(ids);
    notifyListeners();
  }
}
