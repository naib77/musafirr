import '../../config/supabase_config.dart';
import 'auth_service.dart';
import 'mock_auth_service.dart';
import 'supabase_auth_service.dart';

/// Factory for creating the appropriate AuthService implementation.
///
/// Returns [SupabaseAuthService] when Supabase is configured,
/// otherwise returns [MockAuthService] for demo/development.
class AuthServiceFactory {
  AuthServiceFactory._();

  static AuthService? _instance;

  /// Get the auth service instance.
  ///
  /// Uses Supabase when configured, otherwise falls back to mock.
  static AuthService get instance {
    _instance ??= _createService();
    return _instance!;
  }

  /// Create a new service instance (useful for testing).
  static AuthService _createService() {
    if (SupabaseConfig.isConfigured) {
      return SupabaseAuthService.instance;
    }
    return MockAuthService.instance;
  }

  /// Force use of mock service (for testing).
  static void useMock() {
    _instance = MockAuthService.instance;
  }

  /// Force use of Supabase service (requires Supabase to be initialized).
  static void useSupabase() {
    _instance = SupabaseAuthService.instance;
  }

  /// Reset to auto-detect mode.
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  /// Check if using Supabase backend.
  static bool get isUsingSupabase => _instance is SupabaseAuthService;

  /// Check if using mock backend.
  static bool get isUsingMock => _instance is MockAuthService;
}
