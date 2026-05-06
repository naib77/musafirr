import 'package:flutter/foundation.dart';

class FavoritesStateNotifier extends ChangeNotifier {
  final Set<String> _favoriteIds = {};

  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);

  int get count => _favoriteIds.length;

  bool isFavorite(String listingId) {
    return _favoriteIds.contains(listingId);
  }

  void toggleFavorite(String listingId) {
    if (_favoriteIds.contains(listingId)) {
      _favoriteIds.remove(listingId);
    } else {
      _favoriteIds.add(listingId);
    }
    notifyListeners();
  }

  void addFavorite(String listingId) {
    if (!_favoriteIds.contains(listingId)) {
      _favoriteIds.add(listingId);
      notifyListeners();
    }
  }

  void removeFavorite(String listingId) {
    if (_favoriteIds.contains(listingId)) {
      _favoriteIds.remove(listingId);
      notifyListeners();
    }
  }

  void clearAll() {
    _favoriteIds.clear();
    notifyListeners();
  }

  // Bulk operations
  void addAll(Iterable<String> ids) {
    _favoriteIds.addAll(ids);
    notifyListeners();
  }

  void removeAll(Iterable<String> ids) {
    _favoriteIds.removeAll(ids);
    notifyListeners();
  }
}
