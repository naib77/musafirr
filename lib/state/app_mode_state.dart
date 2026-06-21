import 'package:flutter/foundation.dart';
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

  static const String _storageKey = 'app_mode';

  Future<void> _loadSavedMode() async {
    try {
      final prefs = Supabase.instance.client.auth.currentSession;
      // Use local storage via shared preferences pattern
      // For now, we'll use a simple in-memory default that persists per session
      // The mode will be saved when changed

      // Try to get from local storage
      final savedMode = await _getFromLocalStorage();
      if (savedMode != null) {
        _mode = savedMode;
      }
    } catch (e) {
      // Default to guest mode on error
      _mode = AppMode.guest;
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<AppMode?> _getFromLocalStorage() async {
    try {
      // Using web/mobile local storage pattern
      // This is a simplified version - in production you'd use shared_preferences
      final storage = _LocalStorage();
      final value = await storage.read(_storageKey);
      if (value == 'host') return AppMode.host;
      if (value == 'guest') return AppMode.guest;
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _saveToLocalStorage(AppMode mode) async {
    try {
      final storage = _LocalStorage();
      await storage.write(_storageKey, mode == AppMode.host ? 'host' : 'guest');
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

/// Simple local storage abstraction
/// In a real app, this would use shared_preferences package
class _LocalStorage {
  static final Map<String, String> _cache = {};

  Future<String?> read(String key) async {
    return _cache[key];
  }

  Future<void> write(String key, String value) async {
    _cache[key] = value;
  }
}
