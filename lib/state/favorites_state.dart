import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FavoritesStateNotifier extends ChangeNotifier {
  final Set<String> _favoriteIds = {};
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

  /// Toggle favorite status for a listing
  Future<void> toggleFavorite(String listingId) async {
    if (_userId == null) {
      debugPrint('Cannot toggle favorite: user not logged in');
      return;
    }

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
