import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/state/safe_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents the current app mode - Guest or Host
enum AppMode {
  guest,
  host,
}

/// Manages the app mode state (Guest/Host) with persistence
class AppModeStateNotifier extends ChangeNotifier with SafeNotifier {
  AppModeStateNotifier() {
    _loadSavedMode();
  }

  AppMode _mode = AppMode.guest;
  bool _isLoaded = false;

  AppMode get mode => _mode;
  bool get isLoaded => _isLoaded;
  bool get isGuestMode => _mode == AppMode.guest;
  bool get isHostMode => _mode == AppMode.host;

  // Persist the mode PER USER. A global key leaks one user's host mode to the
  // next account that logs in on the same device, dropping a guest-only user
  // into the host dashboard.
  String get _storageKey {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return userId == null ? 'app_mode' : 'app_mode_$userId';
  }

  Future<void> _loadSavedMode() async {
    try {
      // Try to get from local storage (scoped to the current user).
      final savedMode = await _getFromLocalStorage();
      _mode = savedMode ?? AppMode.guest;
    } catch (e) {
      // Default to guest mode on error
      _mode = AppMode.guest;
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<AppMode?> _getFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_storageKey);
      if (value == 'host') return AppMode.host;
      if (value == 'guest') return AppMode.guest;
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveToLocalStorage(AppMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _storageKey, mode == AppMode.host ? 'host' : 'guest');
    } catch (e) {
      // Ignore storage errors
    }
  }

  void setMode(AppMode mode) {
    if (_mode != mode) {
      _mode = mode;
      _saveToLocalStorage(mode);
      notifyListeners();
    }
  }

  void toggleMode() {
    setMode(_mode == AppMode.guest ? AppMode.host : AppMode.guest);
  }

  void switchToGuest() => setMode(AppMode.guest);
  void switchToHost() => setMode(AppMode.host);

  /// Reset to guest mode (e.g., on logout)
  void reset() {
    _mode = AppMode.guest;
    notifyListeners();
  }
}
