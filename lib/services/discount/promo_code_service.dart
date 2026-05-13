import 'dart:math';

import '../../models/discount.dart';
import '../../models/discount_eligibility.dart';
import 'discount_service.dart';

/// Result of promo code validation
class PromoCodeValidationResult {
  const PromoCodeValidationResult._({
    required this.isValid,
    this.discount,
    this.eligibilityResult,
    this.errorMessage,
    this.calculatedAmount,
  });

  factory PromoCodeValidationResult.valid({
    required Discount discount,
    required DiscountEligibilityResult eligibilityResult,
    required double calculatedAmount,
  }) {
    return PromoCodeValidationResult._(
      isValid: true,
      discount: discount,
      eligibilityResult: eligibilityResult,
      calculatedAmount: calculatedAmount,
    );
  }

  factory PromoCodeValidationResult.invalid({
    required String errorMessage,
    Discount? discount,
    DiscountEligibilityResult? eligibilityResult,
  }) {
    return PromoCodeValidationResult._(
      isValid: false,
      errorMessage: errorMessage,
      discount: discount,
      eligibilityResult: eligibilityResult,
    );
  }

  final bool isValid;
  final Discount? discount;
  final DiscountEligibilityResult? eligibilityResult;
  final String? errorMessage;
  final double? calculatedAmount;

  /// Display message for the user
  String get displayMessage {
    if (isValid && discount != null && calculatedAmount != null) {
      return 'You save ৳${calculatedAmount!.toStringAsFixed(0)} with ${discount!.name}';
    }
    return errorMessage ?? 'Invalid promo code';
  }
}

/// Service for promo code operations
class PromoCodeService {
  PromoCodeService({
    required DiscountService discountService,
  }) : _discountService = discountService;

  final DiscountService _discountService;

  /// Validate a promo code for a booking
  Future<PromoCodeValidationResult> validateCode({
    required String code,
    required String userId,
    required double bookingAmount,
    required int nights,
    required DateTime checkInDate,
    String? listingId,
    String? hostId,
  }) async {
    // Clean up the code
    final cleanCode = code.trim().toUpperCase();

    if (cleanCode.isEmpty) {
      return PromoCodeValidationResult.invalid(
        errorMessage: 'Please enter a promo code',
      );
    }

    // Check if code is eligible for first booking
    final isFirstBookingResult =
        await _discountService.isEligibleForFirstBookingDiscount(userId);
    final isFirstBooking = isFirstBookingResult.data ?? false;

    // Build context
    final context = DiscountEligibilityContext(
      userId: userId,
      bookingAmount: bookingAmount,
      nights: nights,
      checkInDate: checkInDate,
      listingId: listingId,
      hostId: hostId,
      isFirstBooking: isFirstBooking,
      isNewUser: isFirstBooking,
    );

    // Validate through discount service
    final result = await _discountService.validatePromoCode(
      code: cleanCode,
      context: context,
    );

    if (result.isFailure) {
      return PromoCodeValidationResult.invalid(
        errorMessage: result.error ?? 'Invalid promo code',
      );
    }

    final eligibilityResult = result.data!;

    if (!eligibilityResult.isEligible) {
      return PromoCodeValidationResult.invalid(
        errorMessage: eligibilityResult.errorMessage ?? 'Code not valid',
        discount: eligibilityResult.discount,
        eligibilityResult: eligibilityResult,
      );
    }

    return PromoCodeValidationResult.valid(
      discount: eligibilityResult.discount,
      eligibilityResult: eligibilityResult,
      calculatedAmount: eligibilityResult.calculatedAmount ?? 0,
    );
  }

  /// Get suggested promo codes for a booking
  Future<List<PromoCodeSuggestion>> getSuggestedCodes({
    required String userId,
    required double bookingAmount,
    required int nights,
    required DateTime checkInDate,
    String? listingId,
    String? hostId,
  }) async {
    final suggestions = <PromoCodeSuggestion>[];

    // Get active discounts with codes
    final discountsResult = await _discountService.getActiveDiscounts();
    if (discountsResult.isFailure || discountsResult.data == null) {
      return suggestions;
    }

    final discountsWithCodes =
        discountsResult.data!.where((d) => d.code != null);

    // Check eligibility for first booking
    final isFirstBookingResult =
        await _discountService.isEligibleForFirstBookingDiscount(userId);
    final isFirstBooking = isFirstBookingResult.data ?? false;

    // Build context
    final context = DiscountEligibilityContext(
      userId: userId,
      bookingAmount: bookingAmount,
      nights: nights,
      checkInDate: checkInDate,
      listingId: listingId,
      hostId: hostId,
      isFirstBooking: isFirstBooking,
      isNewUser: isFirstBooking,
    );

    // Check each code
    for (final discount in discountsWithCodes) {
      final validation = await validateCode(
        code: discount.code!,
        userId: userId,
        bookingAmount: bookingAmount,
        nights: nights,
        checkInDate: checkInDate,
        listingId: listingId,
        hostId: hostId,
      );

      suggestions.add(PromoCodeSuggestion(
        code: discount.code!,
        name: discount.name,
        description: discount.description ?? discount.shortDescription,
        isEligible: validation.isValid,
        savingsAmount: validation.calculatedAmount,
        ineligibilityReason:
            validation.isValid ? null : validation.errorMessage,
        category: discount.category,
        expiresAt: discount.endsAt,
      ));
    }

    // Sort: eligible first, then by savings amount
    suggestions.sort((a, b) {
      if (a.isEligible != b.isEligible) {
        return a.isEligible ? -1 : 1;
      }
      return (b.savingsAmount ?? 0).compareTo(a.savingsAmount ?? 0);
    });

    return suggestions;
  }

  /// Generate a unique referral code for a user
  String generateReferralCode(String userName) {
    final namePart = userName
        .replaceAll(RegExp(r'[^a-zA-Z]'), '')
        .toUpperCase()
        .substring(0, min(4, userName.length));

    final random = Random();
    final randomPart = String.fromCharCodes(
      List.generate(4, (_) => random.nextInt(26) + 65),
    );

    return '$namePart$randomPart';
  }

  /// Format a promo code for display (uppercase, trimmed)
  String formatCode(String code) {
    return code.trim().toUpperCase();
  }

  /// Check if a string looks like a valid promo code format
  bool isValidCodeFormat(String code) {
    final cleaned = code.trim();
    if (cleaned.isEmpty || cleaned.length < 4 || cleaned.length > 20) {
      return false;
    }
    // Allow alphanumeric and some special characters
    return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cleaned);
  }
}

/// Suggestion for a promo code
class PromoCodeSuggestion {
  const PromoCodeSuggestion({
    required this.code,
    required this.name,
    required this.description,
    required this.isEligible,
    this.savingsAmount,
    this.ineligibilityReason,
    this.category,
    this.expiresAt,
  });

  final String code;
  final String name;
  final String description;
  final bool isEligible;
  final double? savingsAmount;
  final String? ineligibilityReason;
  final DiscountCategory? category;
  final DateTime? expiresAt;

  /// Whether this code expires soon (within 7 days)
  bool get expiresSoon {
    if (expiresAt == null) return false;
    return expiresAt!.difference(DateTime.now()).inDays <= 7;
  }

  /// Formatted savings amount
  String get formattedSavings {
    if (savingsAmount == null) return '';
    return 'Save ৳${savingsAmount!.toStringAsFixed(0)}';
  }
}

/// State for promo code input field
enum PromoCodeInputState {
  /// No code entered
  empty,

  /// User is typing
  typing,

  /// Validating the code
  validating,

  /// Code is valid
  valid,

  /// Code is invalid
  invalid,
}

/// Helper class for managing promo code input
class PromoCodeInputManager {
  PromoCodeInputManager({
    required PromoCodeService promoCodeService,
  }) : _promoCodeService = promoCodeService;

  final PromoCodeService _promoCodeService;

  PromoCodeInputState _state = PromoCodeInputState.empty;
  PromoCodeValidationResult? _lastResult;
  String _currentCode = '';

  PromoCodeInputState get state => _state;
  PromoCodeValidationResult? get lastResult => _lastResult;
  String get currentCode => _currentCode;

  /// Called when user types
  void onCodeChanged(String code) {
    _currentCode = code;
    if (code.isEmpty) {
      _state = PromoCodeInputState.empty;
      _lastResult = null;
    } else {
      _state = PromoCodeInputState.typing;
    }
  }

  /// Validate the current code
  Future<PromoCodeValidationResult> validate({
    required String userId,
    required double bookingAmount,
    required int nights,
    required DateTime checkInDate,
    String? listingId,
    String? hostId,
  }) async {
    if (_currentCode.isEmpty) {
      _state = PromoCodeInputState.empty;
      _lastResult = null;
      return PromoCodeValidationResult.invalid(
        errorMessage: 'Please enter a promo code',
      );
    }

    _state = PromoCodeInputState.validating;

    final result = await _promoCodeService.validateCode(
      code: _currentCode,
      userId: userId,
      bookingAmount: bookingAmount,
      nights: nights,
      checkInDate: checkInDate,
      listingId: listingId,
      hostId: hostId,
    );

    _lastResult = result;
    _state = result.isValid
        ? PromoCodeInputState.valid
        : PromoCodeInputState.invalid;

    return result;
  }

  /// Clear the current code
  void clear() {
    _currentCode = '';
    _state = PromoCodeInputState.empty;
    _lastResult = null;
  }
}
