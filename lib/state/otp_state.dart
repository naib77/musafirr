import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/otp_service.dart';

/// Steps in the OTP flow
enum OtpFlowStep {
  phoneEntry,
  otpVerification,
  profileCompletion,
  complete,
}

/// State notifier for OTP-based phone authentication flow
class OtpStateNotifier extends ChangeNotifier {
  OtpFlowStep _currentStep = OtpFlowStep.phoneEntry;
  String? _phoneNumber;
  bool _isLoading = false;
  String? _error;
  int _resendCountdown = 0;
  int _expiryCountdown = 0;
  Timer? _resendTimer;
  Timer? _expiryTimer;

  final OtpService _otpService = OtpService.instance;

  // Getters
  OtpFlowStep get currentStep => _currentStep;
  String? get phoneNumber => _phoneNumber;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get resendCountdown => _resendCountdown;
  int get expiryCountdown => _expiryCountdown;
  bool get canResend => _resendCountdown == 0;

  /// Set phone number and send OTP
  Future<bool> sendOtp(String phoneNumber) async {
    debugPrint('[OTP State] sendOtp called with: $phoneNumber');

    _isLoading = true;
    _error = null;
    notifyListeners();

    final normalized = _otpService.normalizePhoneNumber(phoneNumber);
    _phoneNumber = normalized;

    debugPrint('[OTP State] Calling OtpService.sendOtp for: $normalized');
    final result = await _otpService.sendOtp(normalized);

    debugPrint('[OTP State] Result: success=${result.success}, error=${result.errorMessage}');
    _isLoading = false;

    if (result.success) {
      _currentStep = OtpFlowStep.otpVerification;
      _startResendCountdown();
      _startExpiryCountdown();
      notifyListeners();
      return true;
    }

    _error = result.errorMessage ?? 'Failed to send OTP';
    notifyListeners();
    return false;
  }

  /// Verify OTP
  Future<bool> verifyOtp(String otp) async {
    if (_phoneNumber == null) {
      _error = 'Phone number not set';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    // Simulate slight delay for UX
    await Future.delayed(const Duration(milliseconds: 300));

    final result = _otpService.verifyOtp(_phoneNumber!, otp);

    _isLoading = false;

    if (result.success) {
      _stopTimers();
      _currentStep = OtpFlowStep.profileCompletion;
      notifyListeners();
      return true;
    }

    _error = result.errorMessage;
    if (result.attemptsRemaining != null && result.attemptsRemaining! > 0) {
      _error = '${result.errorMessage}. ${result.attemptsRemaining} attempts remaining.';
    }
    notifyListeners();
    return false;
  }

  /// Resend OTP
  Future<bool> resendOtp() async {
    if (_phoneNumber == null) {
      _error = 'Phone number not set';
      notifyListeners();
      return false;
    }

    if (!canResend) {
      _error = 'Please wait before requesting a new code';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _otpService.sendOtp(_phoneNumber!);

    _isLoading = false;

    if (result.success) {
      _startResendCountdown();
      _startExpiryCountdown();
      notifyListeners();
      return true;
    }

    _error = result.errorMessage ?? 'Failed to resend OTP';
    notifyListeners();
    return false;
  }

  /// Complete profile and move to final step
  void completeProfile() {
    _currentStep = OtpFlowStep.complete;
    notifyListeners();
  }

  /// Go back to phone entry
  void editPhoneNumber() {
    _stopTimers();
    _currentStep = OtpFlowStep.phoneEntry;
    _error = null;
    notifyListeners();
  }

  /// Reset the entire flow
  void reset() {
    _stopTimers();
    _currentStep = OtpFlowStep.phoneEntry;
    _phoneNumber = null;
    _isLoading = false;
    _error = null;
    _resendCountdown = 0;
    _expiryCountdown = 0;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    _resendCountdown = OtpService.resendCooldownSeconds;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _resendCountdown--;
      if (_resendCountdown <= 0) {
        _resendCountdown = 0;
        timer.cancel();
      }
      notifyListeners();
    });
  }

  void _startExpiryCountdown() {
    _expiryTimer?.cancel();
    _expiryCountdown = OtpService.validityMinutes * 60;
    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _expiryCountdown--;
      if (_expiryCountdown <= 0) {
        _expiryCountdown = 0;
        timer.cancel();
        _error = 'OTP has expired. Please request a new one.';
        notifyListeners();
      }
      notifyListeners();
    });
  }

  void _stopTimers() {
    _resendTimer?.cancel();
    _expiryTimer?.cancel();
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }
}
