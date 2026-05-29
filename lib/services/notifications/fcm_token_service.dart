import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_notification_service.dart';

/// Service to manage FCM tokens in Supabase
class FcmTokenService {
  FcmTokenService._();

  static FcmTokenService? _instance;
  static FcmTokenService get instance {
    _instance ??= FcmTokenService._();
    return _instance!;
  }

  SupabaseClient get _supabase => Supabase.instance.client;

  String get _deviceType {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// Save or update FCM token for the current user
  Future<bool> saveToken(String token) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[FcmTokenService] No user logged in, skipping token save');
        return false;
      }

      debugPrint('[FcmTokenService] Saving FCM token for user: $userId');

      // Use the upsert function we created
      await _supabase.rpc('upsert_fcm_token', params: {
        'p_user_id': userId,
        'p_token': token,
        'p_device_type': _deviceType,
        'p_device_name': await _getDeviceName(),
      });

      debugPrint('[FcmTokenService] FCM token saved successfully');
      return true;
    } catch (e) {
      debugPrint('[FcmTokenService] Error saving FCM token: $e');
      return false;
    }
  }

  /// Deactivate FCM token (on logout)
  Future<bool> deactivateToken(String token) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase
          .from('fcm_tokens')
          .update({'is_active': false})
          .eq('user_id', userId)
          .eq('token', token);

      debugPrint('[FcmTokenService] FCM token deactivated');
      return true;
    } catch (e) {
      debugPrint('[FcmTokenService] Error deactivating FCM token: $e');
      return false;
    }
  }

  /// Delete FCM token completely
  Future<bool> deleteToken(String token) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      await _supabase
          .from('fcm_tokens')
          .delete()
          .eq('user_id', userId)
          .eq('token', token);

      debugPrint('[FcmTokenService] FCM token deleted');
      return true;
    } catch (e) {
      debugPrint('[FcmTokenService] Error deleting FCM token: $e');
      return false;
    }
  }

  /// Get device name
  Future<String?> _getDeviceName() async {
    try {
      if (kIsWeb) return 'Web Browser';
      if (Platform.isAndroid) return 'Android Device';
      if (Platform.isIOS) return 'iOS Device';
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Initialize token management - call after user logs in
  Future<void> initializeForUser() async {
    try {
      final pushService = PushNotificationServiceFactory.instance;
      final token = await pushService.getToken();

      if (token != null) {
        await saveToken(token);
      }

      // Listen for token refreshes
      pushService.onTokenRefresh.listen((newToken) {
        saveToken(newToken);
      });
    } catch (e) {
      debugPrint('[FcmTokenService] Error initializing token: $e');
    }
  }

  /// Cleanup on logout
  Future<void> cleanupOnLogout() async {
    try {
      final pushService = PushNotificationServiceFactory.instance;
      final token = await pushService.getToken();

      if (token != null) {
        await deactivateToken(token);
      }
    } catch (e) {
      debugPrint('[FcmTokenService] Error cleaning up token: $e');
    }
  }
}
