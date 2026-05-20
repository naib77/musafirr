import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/supabase_config.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/auth_service_factory.dart';
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
  bool _isExistingUser = false;

  final OtpService _otpService = OtpService.instance;
  late final AuthService _authService;

  OtpStateNotifier() {
    _authService = AuthServiceFactory.instance;
  }

  // Getters
  OtpFlowStep get currentStep => _currentStep;
  String? get phoneNumber => _phoneNumber;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get resendCountdown => _resendCountdown;
  int get expiryCountdown => _expiryCountdown;
  bool get canResend => _resendCountdown == 0;
  bool get isExistingUser => _isExistingUser;

  /// Check if using Supabase for OTP
  bool get _useSupabase => SupabaseConfig.isConfigured;

  /// Set phone number and send OTP
  Future<bool> sendOtp(String phoneNumber) async {
    debugPrint('[OTP State] sendOtp called with: $phoneNumber');
    debugPrint('[OTP State] Using Supabase: $_useSupabase');

    _isLoading = true;
    _error = null;
    notifyListeners();

    final normalized = _otpService.normalizePhoneNumber(phoneNumber);
    _phoneNumber = normalized;

    bool success;
    String? errorMessage;

    if (_useSupabase) {
      // Use Supabase auth OTP
      debugPrint('[OTP State] Calling AuthService.sendOtp for: $normalized');
      final result = await _authService.sendOtp(normalized);
      success = result.success;
      errorMessage = result.error;
    } else {
      // Use local OTP service (mock mode)
      debugPrint('[OTP State] Calling OtpService.sendOtp for: $normalized');
      final result = await _otpService.sendOtp(normalized);
      success = result.success;
      errorMessage = result.errorMessage;
    }

    debugPrint('[OTP State] Result: success=$success, error=$errorMessage');
    _isLoading = false;

    if (success) {
      _currentStep = OtpFlowStep.otpVerification;
      _startResendCountdown();
      _startExpiryCountdown();
      notifyListeners();
      return true;
    }

    _error = errorMessage ?? 'Failed to send OTP';
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

    bool success;
    String? errorMessage;
    int? attemptsRemaining;

    if (_useSupabase) {
      // Use Supabase auth OTP verification
      debugPrint('[OTP State] Calling AuthService.verifyOtp');
      final result = await _authService.verifyOtp(_phoneNumber!, otp);
      success = result.success;
      errorMessage = result.error;
      attemptsRemaining = result.attemptsRemaining;

      if (success) {
        // Use the isExistingUser flag from verifyOtp result
        _isExistingUser = result.isExistingUser;
        debugPrint('[OTP State] isExistingUser: $_isExistingUser');
      }
    } else {
      // Use local OTP service (mock mode)
      // Simulate slight delay for UX
      await Future.delayed(const Duration(milliseconds: 300));

      final result = _otpService.verifyOtp(_phoneNumber!, otp);
      success = result.success;
      errorMessage = result.errorMessage;
      attemptsRemaining = result.attemptsRemaining;

      if (success) {
        // Check if this is an existing user
        final existingUser = _authService.getUserByPhone(_phoneNumber!);
        _isExistingUser = existingUser != null;
      }
    }

    _isLoading = false;

    if (success) {
      _stopTimers();
      // If existing user, skip profile completion
      if (_isExistingUser) {
        _currentStep = OtpFlowStep.complete;
      } else {
        _currentStep = OtpFlowStep.profileCompletion;
      }
      notifyListeners();
      return true;
    }

    _error = errorMessage;
    if (attemptsRemaining != null && attemptsRemaining > 0) {
      _error = '${errorMessage ?? 'Invalid OTP'}. $attemptsRemaining attempts remaining.';
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

    bool success;
    String? errorMessage;

    if (_useSupabase) {
      final result = await _authService.sendOtp(_phoneNumber!);
      success = result.success;
      errorMessage = result.error;
    } else {
      final result = await _otpService.sendOtp(_phoneNumber!);
      success = result.success;
      errorMessage = result.errorMessage;
    }

    _isLoading = false;

    if (success) {
      _startResendCountdown();
      _startExpiryCountdown();
      notifyListeners();
      return true;
    }

    _error = errorMessage ?? 'Failed to resend OTP';
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
    _isExistingUser = false;
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
    _isExistingUser = false;
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
