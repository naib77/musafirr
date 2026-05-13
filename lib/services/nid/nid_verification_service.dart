/// Result of NID verification
class NidVerificationResult {
  const NidVerificationResult({
    required this.success,
    this.errorMessage,
    this.name,
    this.dateOfBirth,
  });

  final bool success;
  final String? errorMessage;
  final String? name; // Name from NID database
  final String? dateOfBirth; // DOB from NID database

  factory NidVerificationResult.success({String? name, String? dateOfBirth}) {
    return NidVerificationResult(
      success: true,
      name: name,
      dateOfBirth: dateOfBirth,
    );
  }

  factory NidVerificationResult.failure(String message) {
    return NidVerificationResult(success: false, errorMessage: message);
  }
}

/// Abstract interface for NID verification services
abstract class NidVerificationService {
  /// Verify NID number with date of birth
  Future<NidVerificationResult> verifyNid({
    required String nidNumber,
    required String dateOfBirth,
  });

  /// Name of the verification service
  String get serviceName;

  /// Whether the service is properly configured
  bool get isConfigured;
}
