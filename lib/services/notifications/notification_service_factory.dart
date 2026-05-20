import '../../config/supabase_config.dart';
import 'in_memory_notification_service.dart';
import 'notification_service.dart';
import 'supabase_notification_service.dart';

/// Factory for creating the appropriate NotificationService implementation.
///
/// Returns [SupabaseNotificationService] when Supabase is configured,
/// otherwise returns [InMemoryNotificationService] for demo/development.
class NotificationServiceFactory {
  NotificationServiceFactory._();

  static NotificationService? _instance;

  /// Get the notification service instance.
  ///
  /// Uses Supabase when configured, otherwise falls back to in-memory.
  static NotificationService get instance {
    _instance ??= _createService();
    return _instance!;
  }

  /// Create a new service instance (useful for testing).
  static NotificationService _createService() {
    if (SupabaseConfig.isConfigured) {
      return SupabaseNotificationService.instance;
    }
    return InMemoryNotificationService.instance;
  }

  /// Force use of in-memory service (for testing).
  static void useInMemory() {
    _instance = InMemoryNotificationService.instance;
  }

  /// Force use of Supabase service (requires Supabase to be initialized).
  static void useSupabase() {
    _instance = SupabaseNotificationService.instance;
  }

  /// Reset to auto-detect mode.
  static void reset() {
    _instance?.dispose();
    _instance = null;
  }

  /// Check if using Supabase backend.
  static bool get isUsingSupabase => _instance is SupabaseNotificationService;

  /// Check if using in-memory backend.
  static bool get isUsingInMemory => _instance is InMemoryNotificationService;
}
