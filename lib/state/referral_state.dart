import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';

import '../models/referral.dart';
import '../services/discount/referral_service.dart';

/// State for referral management
class ReferralStateNotifier extends ChangeNotifier with SafeNotifier {
  ReferralStateNotifier({
    ReferralService? referralService,
  }) : _referralService = referralService ?? InMemoryReferralService();

  final ReferralService _referralService;

  // User's referral info
  UserReferral? _userReferral;
  UserReferral? get userReferral => _userReferral;

  // Referral completions
  List<ReferralCompletion> _completions = [];
  List<ReferralCompletion> get completions => _completions;

  // Referral stats
  ReferralStats? _stats;
  ReferralStats? get stats => _stats;

  // Applied referral (for new users)
  ReferralCompletion? _appliedReferral;
  ReferralCompletion? get appliedReferral => _appliedReferral;

  // Validation result
  ReferralCodeValidation? _validationResult;
  ReferralCodeValidation? get validationResult => _validationResult;

  // Loading states
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isValidating = false;
  bool get isValidating => _isValidating;

  bool _isApplying = false;
  bool get isApplying => _isApplying;

  // Error state
  String? _error;
  String? get error => _error;

  // Current user ID
  String? _userId;
  String? get userId => _userId;

  /// Initialize with user ID
  Future<void> initialize(String userId, {bool forceReload = false}) async {
    if (!forceReload && _userId == userId && _userReferral != null) return;

    _userId = userId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load user referral info
      final referralResult = await _referralService.getUserReferral(userId);
      if (referralResult.isSuccess) {
        _userReferral = referralResult.data;
      } else {
        _error = referralResult.error;
      }

      // Load completions
      final completionsResult =
          await _referralService.getReferralCompletions(userId);
      if (completionsResult.isSuccess) {
        _completions = completionsResult.data ?? [];
      }

      // Load stats
      final statsResult = await _referralService.getReferralStats(userId);
      if (statsResult.isSuccess) {
        _stats = statsResult.data;
      }

      // Check if user was referred
      final referredByResult = await _referralService.getUserReferredBy(userId);
      if (referredByResult.isSuccess) {
        _appliedReferral = referredByResult.data;
      }
    } catch (e) {
      _error = 'Failed to load referral data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh referral data
  Future<void> refresh() async {
    if (_userId == null) return;
    await initialize(_userId!, forceReload: true);
  }

  /// Validate a referral code
  Future<bool> validateCode(String code) async {
    _isValidating = true;
    _validationResult = null;
    _error = null;
    notifyListeners();

    try {
      final result = await _referralService.validateReferralCode(code);

      if (result.isFailure) {
        _error = result.error;
        _isValidating = false;
        notifyListeners();
        return false;
      }

      _validationResult = result.data;
      _isValidating = false;
      notifyListeners();

      return _validationResult?.isValid ?? false;
    } catch (e) {
      _error = 'Failed to validate code: $e';
      _isValidating = false;
      notifyListeners();
      return false;
    }
  }

  /// Apply a referral code for a new user
  Future<bool> applyCode(String refereeId, String code) async {
    _isApplying = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _referralService.applyReferralCode(
        refereeId: refereeId,
        referralCode: code,
      );

      if (result.isFailure) {
        _error = result.error;
        _isApplying = false;
        notifyListeners();
        return false;
      }

      _appliedReferral = result.data;
      _isApplying = false;
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Failed to apply code: $e';
      _isApplying = false;
      notifyListeners();
      return false;
    }
  }

  /// Generate a new referral code
  Future<String?> generateNewCode() async {
    if (_userId == null) return null;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _referralService.generateReferralCode(_userId!);

      if (result.isFailure) {
        _error = result.error;
        _isLoading = false;
        notifyListeners();
        return null;
      }

      // Refresh to get updated referral info
      await refresh();

      return result.data;
    } catch (e) {
      _error = 'Failed to generate code: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Clear validation result
  void clearValidation() {
    _validationResult = null;
    _error = null;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get share message for referral
  String get shareMessage => _userReferral?.shareMessage ?? '';

  /// Get share link
  String get shareLink => _userReferral?.shareLink ?? '';

  /// Get referral code
  String get referralCode => _userReferral?.referralCode ?? '';

  /// Get reward amount for referrer
  double get referrerRewardAmount => _userReferral?.referrerRewardAmount ?? 500;

  /// Get discount amount for referee
  double get refereeDiscountAmount =>
      _userReferral?.refereeDiscountAmount ?? 500;

  /// Get pending completions
  List<ReferralCompletion> get pendingCompletions =>
      _completions.where((c) => c.isPending).toList();

  /// Get completed completions
  List<ReferralCompletion> get completedCompletions =>
      _completions.where((c) => c.isComplete).toList();

  /// Check if user has applied a referral code
  bool get hasAppliedReferral => _appliedReferral != null;

  /// Get applied referral discount amount
  double? get appliedReferralDiscount {
    if (_appliedReferral == null || _validationResult == null) return null;
    return _validationResult!.discountAmount;
  }

  /// Dispose resources
  @override
  void dispose() {
    super.dispose();
  }
}
