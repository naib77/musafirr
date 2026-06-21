import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';

import '../models/applied_discount.dart';
import '../models/discount.dart';
import '../models/discount_eligibility.dart';
import '../services/discount/discount_service.dart';
import '../services/discount/promo_code_service.dart';

/// State notifier for discount-related UI
class DiscountStateNotifier extends ChangeNotifier with SafeNotifier {
  DiscountStateNotifier({
    required DiscountService discountService,
    required PromoCodeService promoCodeService,
    required String userId,
  })  : _discountService = discountService,
        _promoCodeService = promoCodeService,
        _userId = userId;

  final DiscountService _discountService;
  final PromoCodeService _promoCodeService;
  final String _userId;

  // Loading states
  bool _isLoading = false;
  bool _isValidatingCode = false;
  bool _isApplyingDiscounts = false;

  // Data
  List<Discount> _availableDiscounts = [];
  List<PromoCodeSuggestion> _suggestedCodes = [];
  DiscountSummary? _appliedDiscountSummary;
  PromoCodeValidationResult? _promoCodeValidationResult;
  List<AppliedDiscount> _userDiscountHistory = [];

  // Booking context
  double _bookingAmount = 0;
  int _nights = 1;
  DateTime _checkInDate = DateTime.now();
  String? _listingId;
  String? _hostId;

  // Error handling
  String? _error;

  // Getters
  bool get isLoading => _isLoading;
  bool get isValidatingCode => _isValidatingCode;
  bool get isApplyingDiscounts => _isApplyingDiscounts;
  List<Discount> get availableDiscounts => List.unmodifiable(_availableDiscounts);
  List<PromoCodeSuggestion> get suggestedCodes => List.unmodifiable(_suggestedCodes);
  DiscountSummary? get appliedDiscountSummary => _appliedDiscountSummary;
  PromoCodeValidationResult? get promoCodeValidationResult =>
      _promoCodeValidationResult;
  List<AppliedDiscount> get userDiscountHistory =>
      List.unmodifiable(_userDiscountHistory);
  String? get error => _error;

  // Computed getters
  bool get hasAppliedDiscounts =>
      _appliedDiscountSummary != null && _appliedDiscountSummary!.hasDiscounts;

  double get totalSavings => _appliedDiscountSummary?.totalDiscountAmount ?? 0;

  double get finalAmount =>
      _appliedDiscountSummary?.finalAmount ?? _bookingAmount;

  bool get hasValidPromoCode =>
      _promoCodeValidationResult != null && _promoCodeValidationResult!.isValid;

  int get availableDiscountCount => _availableDiscounts.length;

  int get eligibleSuggestedCodeCount =>
      _suggestedCodes.where((s) => s.isEligible).length;

  /// Set booking context for discount calculations
  void setBookingContext({
    required double bookingAmount,
    required int nights,
    required DateTime checkInDate,
    String? listingId,
    String? hostId,
  }) {
    _bookingAmount = bookingAmount;
    _nights = nights;
    _checkInDate = checkInDate;
    _listingId = listingId;
    _hostId = hostId;

    // Clear previous results when context changes
    _appliedDiscountSummary = null;
    _promoCodeValidationResult = null;
    notifyListeners();
  }

  /// Load available discounts for the current listing
  Future<void> loadAvailableDiscounts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = _listingId != null
          ? await _discountService.getDiscountsForListing(_listingId!)
          : await _discountService.getActiveDiscounts();

      if (result.isSuccess && result.data != null) {
        _availableDiscounts = result.data!;
      } else {
        _error = result.error ?? 'Failed to load discounts';
      }
    } catch (e) {
      _error = 'Error loading discounts: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load suggested promo codes for the booking
  Future<void> loadSuggestedCodes() async {
    if (_bookingAmount <= 0) return;

    try {
      _suggestedCodes = await _promoCodeService.getSuggestedCodes(
        userId: _userId,
        bookingAmount: _bookingAmount,
        nights: _nights,
        checkInDate: _checkInDate,
        listingId: _listingId,
        hostId: _hostId,
      );
      notifyListeners();
    } catch (e) {
      // Silently fail - suggestions are optional
      debugPrint('Failed to load suggested codes: $e');
    }
  }

  /// Validate a promo code
  Future<bool> validatePromoCode(String code) async {
    if (code.trim().isEmpty) {
      _promoCodeValidationResult = null;
      notifyListeners();
      return false;
    }

    _isValidatingCode = true;
    _error = null;
    notifyListeners();

    try {
      _promoCodeValidationResult = await _promoCodeService.validateCode(
        code: code,
        userId: _userId,
        bookingAmount: _bookingAmount,
        nights: _nights,
        checkInDate: _checkInDate,
        listingId: _listingId,
        hostId: _hostId,
      );
    } catch (e) {
      _promoCodeValidationResult = PromoCodeValidationResult.invalid(
        errorMessage: 'Error validating code: $e',
      );
    }

    _isValidatingCode = false;
    notifyListeners();

    return _promoCodeValidationResult?.isValid ?? false;
  }

  /// Clear the promo code validation result
  void clearPromoCode() {
    _promoCodeValidationResult = null;
    notifyListeners();
  }

  /// Apply discounts to the booking
  Future<bool> applyDiscounts({String? promoCode}) async {
    if (_bookingAmount <= 0) return false;

    _isApplyingDiscounts = true;
    _error = null;
    notifyListeners();

    try {
      final request = ApplyDiscountsRequest(
        userId: _userId,
        bookingAmount: _bookingAmount,
        nights: _nights,
        checkInDate: _checkInDate,
        listingId: _listingId,
        hostId: _hostId,
        promoCode: promoCode ?? _promoCodeValidationResult?.discount?.code,
        autoApply: true,
      );

      final result = await _discountService.applyDiscounts(request);

      if (result.isSuccess && result.data != null) {
        _appliedDiscountSummary = result.data;
        _isApplyingDiscounts = false;
        notifyListeners();
        return true;
      } else {
        _error = result.error ?? 'Failed to apply discounts';
      }
    } catch (e) {
      _error = 'Error applying discounts: $e';
    }

    _isApplyingDiscounts = false;
    notifyListeners();
    return false;
  }

  /// Calculate potential savings without actually applying
  Future<DiscountSummary?> calculatePotentialSavings({String? promoCode}) async {
    if (_bookingAmount <= 0) return null;

    try {
      final request = ApplyDiscountsRequest(
        userId: _userId,
        bookingAmount: _bookingAmount,
        nights: _nights,
        checkInDate: _checkInDate,
        listingId: _listingId,
        hostId: _hostId,
        promoCode: promoCode,
        autoApply: true,
      );

      // Note: In a real implementation, this would be a preview method
      // that doesn't record the usage
      final result = await _discountService.applyDiscounts(request);

      if (result.isSuccess && result.data != null) {
        return result.data;
      }
    } catch (e) {
      debugPrint('Error calculating potential savings: $e');
    }

    return null;
  }

  /// Load user's discount usage history
  Future<void> loadUserDiscountHistory() async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _discountService.getUserAppliedDiscounts(_userId);

      if (result.isSuccess && result.data != null) {
        _userDiscountHistory = result.data!;
      }
    } catch (e) {
      debugPrint('Error loading discount history: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Check if user is eligible for first booking discount
  Future<bool> checkFirstBookingEligibility() async {
    final result =
        await _discountService.isEligibleForFirstBookingDiscount(_userId);
    return result.data ?? false;
  }

  /// Apply a suggested code
  Future<bool> applySuggestedCode(PromoCodeSuggestion suggestion) async {
    if (!suggestion.isEligible) return false;

    final isValid = await validatePromoCode(suggestion.code);
    if (!isValid) return false;

    return applyDiscounts(promoCode: suggestion.code);
  }

  /// Remove applied discounts
  void clearAppliedDiscounts() {
    _appliedDiscountSummary = null;
    _promoCodeValidationResult = null;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get the best available discount
  Discount? getBestAvailableDiscount() {
    if (_availableDiscounts.isEmpty) return null;

    // Find the discount that would give the highest savings
    Discount? best;
    double bestAmount = 0;

    for (final discount in _availableDiscounts) {
      final context = DiscountEligibilityContext(
        userId: _userId,
        bookingAmount: _bookingAmount,
        nights: _nights,
        checkInDate: _checkInDate,
        listingId: _listingId,
        hostId: _hostId,
      );

      final result = DiscountEligibilityChecker.check(discount, context);
      if (result.isEligible && (result.calculatedAmount ?? 0) > bestAmount) {
        best = discount;
        bestAmount = result.calculatedAmount ?? 0;
      }
    }

    return best;
  }

  /// Get discounts by category
  List<Discount> getDiscountsByCategory(DiscountCategory category) {
    return _availableDiscounts.where((d) => d.category == category).toList();
  }

  /// Get auto-applicable discounts (no code required)
  List<Discount> getAutoApplicableDiscounts() {
    return _availableDiscounts.where((d) => d.code == null).toList();
  }

  /// Get discounts with codes
  List<Discount> getDiscountsWithCodes() {
    return _availableDiscounts.where((d) => d.code != null).toList();
  }
}

/// Simplified state for just promo code input
class PromoCodeInputState extends ChangeNotifier with SafeNotifier {
  PromoCodeInputState({
    required PromoCodeService promoCodeService,
  }) : _manager = PromoCodeInputManager(promoCodeService: promoCodeService);

  final PromoCodeInputManager _manager;

  String _code = '';
  bool _isValidating = false;

  String get code => _code;
  bool get isValidating => _isValidating;
  PromoCodeInputState get state => this;
  PromoCodeValidationResult? get validationResult => _manager.lastResult;

  bool get isEmpty => _code.isEmpty;
  bool get isValid => _manager.lastResult?.isValid ?? false;
  bool get isInvalid =>
      _manager.lastResult != null && !_manager.lastResult!.isValid;

  String? get errorMessage => _manager.lastResult?.errorMessage;
  String? get successMessage =>
      isValid ? _manager.lastResult?.displayMessage : null;

  void onCodeChanged(String value) {
    _code = value;
    _manager.onCodeChanged(value);
    notifyListeners();
  }

  Future<bool> validate({
    required String userId,
    required double bookingAmount,
    required int nights,
    required DateTime checkInDate,
    String? listingId,
    String? hostId,
  }) async {
    _isValidating = true;
    notifyListeners();

    final result = await _manager.validate(
      userId: userId,
      bookingAmount: bookingAmount,
      nights: nights,
      checkInDate: checkInDate,
      listingId: listingId,
      hostId: hostId,
    );

    _isValidating = false;
    notifyListeners();

    return result.isValid;
  }

  void clear() {
    _code = '';
    _manager.clear();
    notifyListeners();
  }
}
