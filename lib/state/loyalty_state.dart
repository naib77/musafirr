import 'package:flutter/foundation.dart';
import '../core/state/safe_notifier.dart';

import '../models/loyalty_tier.dart';
import '../services/discount/loyalty_service.dart';

/// State for loyalty program management
class LoyaltyStateNotifier extends ChangeNotifier with SafeNotifier {
  LoyaltyStateNotifier({
    LoyaltyService? loyaltyService,
  }) : _loyaltyService = loyaltyService ?? InMemoryLoyaltyService();

  final LoyaltyService _loyaltyService;

  // All available tiers
  List<LoyaltyTier> _tiers = [];
  List<LoyaltyTier> get tiers => _tiers;

  // User's loyalty status
  UserLoyalty? _userLoyalty;
  UserLoyalty? get userLoyalty => _userLoyalty;

  // Progress towards next tier
  TierProgress? _progress;
  TierProgress? get progress => _progress;

  // Recent tier upgrade event
  TierUpgradeEvent? _recentUpgrade;
  TierUpgradeEvent? get recentUpgrade => _recentUpgrade;

  // Loading state
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // Error state
  String? _error;
  String? get error => _error;

  // Current user ID
  String? _userId;
  String? get userId => _userId;

  /// Initialize with user ID
  Future<void> initialize(String userId) async {
    if (_userId == userId && _userLoyalty != null) return;

    _userId = userId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load all tiers
      final tiersResult = await _loyaltyService.getAllTiers();
      if (tiersResult.isSuccess) {
        _tiers = tiersResult.data ?? [];
      }

      // Load user loyalty
      final loyaltyResult = await _loyaltyService.getUserLoyalty(userId);
      if (loyaltyResult.isSuccess) {
        _userLoyalty = loyaltyResult.data;
      } else {
        _error = loyaltyResult.error;
      }

      // Load progress
      final progressResult = await _loyaltyService.getUserTierProgress(userId);
      if (progressResult.isSuccess) {
        _progress = progressResult.data;
      }
    } catch (e) {
      _error = 'Failed to load loyalty data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh loyalty data
  Future<void> refresh() async {
    if (_userId == null) return;

    // Clear recent upgrade on refresh
    _recentUpgrade = null;

    await initialize(_userId!);
  }

  /// Record a booking and check for tier upgrade
  Future<bool> recordBooking({
    required int nights,
    required double amount,
  }) async {
    if (_userId == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Record the booking
      final bookingResult = await _loyaltyService.recordBooking(
        userId: _userId!,
        nights: nights,
        amount: amount,
      );

      if (bookingResult.isFailure) {
        _error = bookingResult.error;
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _userLoyalty = bookingResult.data;

      // Check for tier upgrade
      final upgradeResult =
          await _loyaltyService.checkAndUpgradeTier(_userId!);

      if (upgradeResult.isSuccess && upgradeResult.data != null) {
        _recentUpgrade = upgradeResult.data;

        // Reload user loyalty to get updated tier
        final loyaltyResult = await _loyaltyService.getUserLoyalty(_userId!);
        if (loyaltyResult.isSuccess) {
          _userLoyalty = loyaltyResult.data;
        }
      }

      // Reload progress
      final progressResult =
          await _loyaltyService.getUserTierProgress(_userId!);
      if (progressResult.isSuccess) {
        _progress = progressResult.data;
      }

      _isLoading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Failed to record booking: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Clear recent upgrade notification
  void clearUpgradeNotification() {
    _recentUpgrade = null;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get current tier
  LoyaltyTier? get currentTier => _userLoyalty?.currentTier;

  /// Get next tier (if any)
  LoyaltyTier? get nextTier => _progress?.nextTier;

  /// Get tier name
  String get tierName => _userLoyalty?.tierName ?? 'Bronze';

  /// Get tier level
  LoyaltyTierLevel get tierLevel =>
      _userLoyalty?.tierLevel ?? LoyaltyTierLevel.bronze;

  /// Get discount percentage
  double get discountPercentage => _userLoyalty?.discountPercentage ?? 0;

  /// Get total bookings
  int get totalBookings => _userLoyalty?.totalBookings ?? 0;

  /// Get total nights stayed
  int get totalNightsStayed => _userLoyalty?.totalNightsStayed ?? 0;

  /// Get total amount spent
  double get totalAmountSpent => _userLoyalty?.totalAmountSpent ?? 0;

  /// Get loyalty points
  int get loyaltyPoints => _userLoyalty?.loyaltyPoints ?? 0;

  /// Get credits balance
  double get creditsBalance => _userLoyalty?.creditsBalance ?? 0;

  /// Check if user has any tier benefits
  bool get hasTierBenefits => discountPercentage > 0;

  /// Check if there's a next tier to achieve
  bool get hasNextTier => _progress?.hasNextTier ?? false;

  /// Get overall progress percentage
  double get overallProgress => _progress?.overallProgress ?? 0;

  /// Get bookings progress
  int get bookingsProgress => _progress?.bookingsProgress ?? 0;

  /// Get bookings required for next tier
  int get bookingsRequired => _progress?.bookingsRequired ?? 0;

  /// Get nights progress
  int get nightsProgress => _progress?.nightsProgress ?? 0;

  /// Get nights required for next tier
  int get nightsRequired => _progress?.nightsRequired ?? 0;

  /// Get spent progress
  double get spentProgress => _progress?.spentProgress ?? 0;

  /// Get spent required for next tier
  double get spentRequired => _progress?.spentRequired ?? 0;

  /// Get bookings remaining for next tier
  int get bookingsRemaining => _progress?.bookingsRemaining ?? 0;

  /// Get nights remaining for next tier
  int get nightsRemaining => _progress?.nightsRemaining ?? 0;

  /// Get amount remaining to spend for next tier
  double get spentRemaining => _progress?.spentRemaining ?? 0;

  /// Get tier benefits list
  List<String> get tierBenefits => currentTier?.benefitsList ?? [];

  /// Check if user was recently upgraded
  bool get wasRecentlyUpgraded => _userLoyalty?.wasRecentlyUpgraded ?? false;

  /// Get tier by level
  LoyaltyTier? getTierByLevel(int level) {
    return _tiers.cast<LoyaltyTier?>().firstWhere(
          (t) => t?.level == level,
          orElse: () => null,
        );
  }

  /// Get upgrade message
  String? get upgradeMessage => _recentUpgrade?.message;

  /// Get new benefits from upgrade
  List<String> get newBenefitsFromUpgrade =>
      _recentUpgrade?.newBenefits ?? [];

  /// Dispose resources
  @override
  void dispose() {
    super.dispose();
  }
}
