import '../../models/discount.dart';
import '../../models/loyalty_tier.dart';

/// Result wrapper for loyalty operations
class LoyaltyResult<T> {
  const LoyaltyResult.success(this.data)
      : error = null,
        errorCode = null;
  const LoyaltyResult.failure(this.error, [this.errorCode]) : data = null;

  final T? data;
  final String? error;
  final String? errorCode;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

/// Tier upgrade event
class TierUpgradeEvent {
  const TierUpgradeEvent({
    required this.previousTier,
    required this.newTier,
    required this.upgradedAt,
  });

  final LoyaltyTier previousTier;
  final LoyaltyTier newTier;
  final DateTime upgradedAt;

  String get message =>
      'Congratulations! You\'ve been upgraded to ${newTier.name} tier!';

  List<String> get newBenefits {
    final oldBenefits = previousTier.benefitsList.toSet();
    return newTier.benefitsList.where((b) => !oldBenefits.contains(b)).toList();
  }
}

/// Abstract interface for loyalty service
abstract class LoyaltyService {
  /// Get all loyalty tiers
  Future<LoyaltyResult<List<LoyaltyTier>>> getAllTiers();

  /// Get a specific tier by ID
  Future<LoyaltyResult<LoyaltyTier>> getTier(String tierId);

  /// Get user's loyalty status
  Future<LoyaltyResult<UserLoyalty>> getUserLoyalty(String userId);

  /// Get user's progress towards next tier
  Future<LoyaltyResult<TierProgress>> getUserTierProgress(String userId);

  /// Update user's loyalty stats after a booking
  Future<LoyaltyResult<UserLoyalty>> recordBooking({
    required String userId,
    required int nights,
    required double amount,
  });

  /// Check and upgrade tier if eligible
  Future<LoyaltyResult<TierUpgradeEvent?>> checkAndUpgradeTier(String userId);

  /// Get loyalty discount for user
  Future<LoyaltyResult<Discount?>> getLoyaltyDiscount(String userId);

  /// Calculate tier from stats
  LoyaltyTier calculateTierFromStats({
    required int totalBookings,
    required int totalNights,
    required double totalSpent,
    required List<LoyaltyTier> tiers,
  });
}

/// In-memory implementation for development
class InMemoryLoyaltyService implements LoyaltyService {
  InMemoryLoyaltyService() {
    _initializeTiers();
    _initializeSampleData();
  }

  final List<LoyaltyTier> _tiers = [];
  final Map<String, UserLoyalty> _userLoyalty = {};

  void _initializeTiers() {
    _tiers.addAll([
      LoyaltyTier(
        id: 'tier_bronze',
        name: 'Bronze',
        level: 1,
        minBookings: 0,
        minNightsStayed: 0,
        minTotalSpent: 0,
        discountPercentage: 0,
        prioritySupport: false,
        freeCancellationWindow: 24,
        earlyAccessHours: 0,
        badgeColor: '#CD7F32',
        iconName: 'star_border',
      ),
      LoyaltyTier(
        id: 'tier_silver',
        name: 'Silver',
        level: 2,
        minBookings: 3,
        minNightsStayed: 10,
        minTotalSpent: 15000,
        discountPercentage: 3,
        prioritySupport: false,
        freeCancellationWindow: 48,
        earlyAccessHours: 12,
        badgeColor: '#C0C0C0',
        iconName: 'star_half',
      ),
      LoyaltyTier(
        id: 'tier_gold',
        name: 'Gold',
        level: 3,
        minBookings: 7,
        minNightsStayed: 25,
        minTotalSpent: 50000,
        discountPercentage: 5,
        prioritySupport: true,
        freeCancellationWindow: 72,
        earlyAccessHours: 24,
        badgeColor: '#FFD700',
        iconName: 'star',
      ),
      LoyaltyTier(
        id: 'tier_platinum',
        name: 'Platinum',
        level: 4,
        minBookings: 15,
        minNightsStayed: 50,
        minTotalSpent: 150000,
        discountPercentage: 8,
        prioritySupport: true,
        freeCancellationWindow: 168,
        earlyAccessHours: 48,
        badgeColor: '#E5E4E2',
        iconName: 'workspace_premium',
      ),
    ]);
  }

  void _initializeSampleData() {
    // Sample user loyalty - Silver tier
    _userLoyalty['user_1'] = UserLoyalty(
      id: 'loyalty_1',
      userId: 'user_1',
      currentTier: _tiers[1], // Silver
      currentTierId: 'tier_silver',
      totalBookings: 5,
      totalNightsStayed: 18,
      totalAmountSpent: 35000,
      loyaltyPoints: 350,
      createdAt: DateTime.now().subtract(const Duration(days: 180)),
    );

    // Sample user loyalty - Gold tier
    _userLoyalty['user_2'] = UserLoyalty(
      id: 'loyalty_2',
      userId: 'user_2',
      currentTier: _tiers[2], // Gold
      currentTierId: 'tier_gold',
      totalBookings: 12,
      totalNightsStayed: 45,
      totalAmountSpent: 120000,
      loyaltyPoints: 1200,
      tierUpgradedAt: DateTime.now().subtract(const Duration(days: 30)),
      previousTierId: 'tier_silver',
      createdAt: DateTime.now().subtract(const Duration(days: 365)),
    );
  }

  @override
  Future<LoyaltyResult<List<LoyaltyTier>>> getAllTiers() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return LoyaltyResult.success(List.unmodifiable(_tiers));
  }

  @override
  Future<LoyaltyResult<LoyaltyTier>> getTier(String tierId) async {
    await Future.delayed(const Duration(milliseconds: 100));

    final tier = _tiers.cast<LoyaltyTier?>().firstWhere(
          (t) => t?.id == tierId,
          orElse: () => null,
        );

    if (tier == null) {
      return const LoyaltyResult.failure('Tier not found', 'NOT_FOUND');
    }

    return LoyaltyResult.success(tier);
  }

  @override
  Future<LoyaltyResult<UserLoyalty>> getUserLoyalty(String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    if (_userLoyalty.containsKey(userId)) {
      return LoyaltyResult.success(_userLoyalty[userId]!);
    }

    // Create new user loyalty with Bronze tier
    final bronzeTier = _tiers.first;
    final loyalty = UserLoyalty(
      id: 'loyalty_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      currentTier: bronzeTier,
      currentTierId: bronzeTier.id,
      createdAt: DateTime.now(),
    );

    _userLoyalty[userId] = loyalty;
    return LoyaltyResult.success(loyalty);
  }

  @override
  Future<LoyaltyResult<TierProgress>> getUserTierProgress(String userId) async {
    final loyaltyResult = await getUserLoyalty(userId);

    if (loyaltyResult.isFailure) {
      return LoyaltyResult.failure(loyaltyResult.error!);
    }

    final loyalty = loyaltyResult.data!;
    final progress = TierProgress.fromUserLoyalty(loyalty, _tiers);

    return LoyaltyResult.success(progress);
  }

  @override
  Future<LoyaltyResult<UserLoyalty>> recordBooking({
    required String userId,
    required int nights,
    required double amount,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final loyaltyResult = await getUserLoyalty(userId);
    if (loyaltyResult.isFailure) {
      return LoyaltyResult.failure(loyaltyResult.error!);
    }

    final loyalty = loyaltyResult.data!;

    // Update stats
    final updatedLoyalty = loyalty.copyWith(
      totalBookings: loyalty.totalBookings + 1,
      totalNightsStayed: loyalty.totalNightsStayed + nights,
      totalAmountSpent: loyalty.totalAmountSpent + amount,
      loyaltyPoints:
          loyalty.loyaltyPoints + (amount ~/ 100), // 1 point per ৳100
      updatedAt: DateTime.now(),
    );

    _userLoyalty[userId] = updatedLoyalty;

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║              LOYALTY STATS UPDATED                           ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ User: $userId');
    print('║ Total Bookings: ${updatedLoyalty.totalBookings}');
    print('║ Total Nights: ${updatedLoyalty.totalNightsStayed}');
    print(
        '║ Total Spent: ৳${updatedLoyalty.totalAmountSpent.toStringAsFixed(0)}');
    print('║ Points: ${updatedLoyalty.loyaltyPoints}');
    print('╚══════════════════════════════════════════════════════════════╝');

    return LoyaltyResult.success(updatedLoyalty);
  }

  @override
  Future<LoyaltyResult<TierUpgradeEvent?>> checkAndUpgradeTier(
      String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final loyaltyResult = await getUserLoyalty(userId);
    if (loyaltyResult.isFailure) {
      return LoyaltyResult.failure(loyaltyResult.error!);
    }

    final loyalty = loyaltyResult.data!;
    final currentTier = loyalty.currentTier ?? _tiers.first;

    // Calculate eligible tier
    final eligibleTier = calculateTierFromStats(
      totalBookings: loyalty.totalBookings,
      totalNights: loyalty.totalNightsStayed,
      totalSpent: loyalty.totalAmountSpent,
      tiers: _tiers,
    );

    // Check if upgrade is possible
    if (eligibleTier.level <= currentTier.level) {
      return const LoyaltyResult.success(null); // No upgrade
    }

    // Perform upgrade
    final updatedLoyalty = loyalty.copyWith(
      currentTier: eligibleTier,
      currentTierId: eligibleTier.id,
      previousTierId: currentTier.id,
      tierUpgradedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _userLoyalty[userId] = updatedLoyalty;

    final upgradeEvent = TierUpgradeEvent(
      previousTier: currentTier,
      newTier: eligibleTier,
      upgradedAt: DateTime.now(),
    );

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║              TIER UPGRADE!                                   ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ User: $userId');
    print('║ ${currentTier.name} → ${eligibleTier.name}');
    print('║ New Discount: ${eligibleTier.discountPercentage}%');
    print('╚══════════════════════════════════════════════════════════════╝');

    return LoyaltyResult.success(upgradeEvent);
  }

  @override
  Future<LoyaltyResult<Discount?>> getLoyaltyDiscount(String userId) async {
    final loyaltyResult = await getUserLoyalty(userId);
    if (loyaltyResult.isFailure) {
      return LoyaltyResult.failure(loyaltyResult.error!);
    }

    final loyalty = loyaltyResult.data!;
    final tier = loyalty.currentTier;

    if (tier == null || tier.discountPercentage <= 0) {
      return const LoyaltyResult.success(null);
    }

    // Create a loyalty discount
    final discount = Discount(
      id: 'loyalty_discount_${tier.id}',
      name: '${tier.name} Member Discount',
      description:
          '${tier.discountPercentage.toStringAsFixed(0)}% off for ${tier.name} members',
      type: DiscountType.percentage,
      category: DiscountCategory.loyalty,
      status: DiscountStatus.active,
      value: tier.discountPercentage,
      startsAt: DateTime.now().subtract(const Duration(days: 365)),
      stackingBehavior: StackingBehavior.stackable,
      stackableWithCategories: [
        DiscountCategory.platform,
        DiscountCategory.host,
        DiscountCategory.referral,
      ],
      priority: 10, // High priority
    );

    return LoyaltyResult.success(discount);
  }

  @override
  LoyaltyTier calculateTierFromStats({
    required int totalBookings,
    required int totalNights,
    required double totalSpent,
    required List<LoyaltyTier> tiers,
  }) {
    // Sort tiers by level descending to find highest eligible
    final sortedTiers = List<LoyaltyTier>.from(tiers)
      ..sort((a, b) => b.level.compareTo(a.level));

    for (final tier in sortedTiers) {
      if (totalBookings >= tier.minBookings &&
          totalNights >= tier.minNightsStayed &&
          totalSpent >= tier.minTotalSpent) {
        return tier;
      }
    }

    // Default to lowest tier
    return tiers.reduce((a, b) => a.level < b.level ? a : b);
  }

  /// For testing: set user loyalty
  void setUserLoyalty(String userId, UserLoyalty loyalty) {
    _userLoyalty[userId] = loyalty;
  }

  /// For testing: get tier by name
  LoyaltyTier? getTierByName(String name) {
    return _tiers.cast<LoyaltyTier?>().firstWhere(
          (t) => t?.name.toLowerCase() == name.toLowerCase(),
          orElse: () => null,
        );
  }
}
