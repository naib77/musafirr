import 'package:flutter/foundation.dart';

import 'nid_verification_service.dart';

/// Bypass NID verification service for development
/// Always returns success without actual verification
class BypassNidVerificationService implements NidVerificationService {
  @override
  String get serviceName => 'Bypass (Development)';

  @override
  bool get isConfigured => true;

  @override
  Future<NidVerificationResult> verifyNid({
    required String nidNumber,
    required String dateOfBirth,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // Print verification attempt to console
    debugPrint('');
    debugPrint('╔══════════════════════════════════════════════════════════╗');
    debugPrint('║              NID VERIFICATION (DEV BYPASS)                ║');
    debugPrint('╠══════════════════════════════════════════════════════════╣');
    debugPrint('║ NID Number: $nidNumber');
    debugPrint('║ Date of Birth: $dateOfBirth');
    debugPrint('║ Status: VERIFIED (Bypass Mode)');
    debugPrint('╚══════════════════════════════════════════════════════════╝');
    debugPrint('');

    // Always return success in development
    return NidVerificationResult.success(
      name: 'Verified User',
      dateOfBirth: dateOfBirth,
    );
  }
}

/// Factory to get NID verification service
class NidVerificationFactory {
  NidVerificationFactory._();

  static NidVerificationService? _instance;

  /// Get the NID verification service
  /// In development, always returns BypassNidVerificationService
  static NidVerificationService getService() {
    _instance ??= BypassNidVerificationService();
    return _instance!;
  }

  /// Reset the service instance (useful for testing)
  static void reset() {
    _instance = null;
  }
}
