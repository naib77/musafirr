import 'dart:math';

import '../../models/referral.dart';

/// Result wrapper for referral operations
class ReferralResult<T> {
  const ReferralResult.success(this.data)
      : error = null,
        errorCode = null;
  const ReferralResult.failure(this.error, [this.errorCode]) : data = null;

  final T? data;
  final String? error;
  final String? errorCode;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;
}

/// Abstract interface for referral service
abstract class ReferralService {
  /// Get user's referral info (creates one if doesn't exist)
  Future<ReferralResult<UserReferral>> getUserReferral(String userId);

  /// Get referral completions for a user
  Future<ReferralResult<List<ReferralCompletion>>> getReferralCompletions(
      String userId);

  /// Validate a referral code
  Future<ReferralResult<ReferralCodeValidation>> validateReferralCode(
      String code);

  /// Apply a referral code for a new user
  Future<ReferralResult<ReferralCompletion>> applyReferralCode({
    required String refereeId,
    required String referralCode,
  });

  /// Mark referral as discount used
  Future<ReferralResult<void>> markDiscountUsed(String referralCompletionId);

  /// Complete a referral (after first booking)
  Future<ReferralResult<void>> completeReferral({
    required String referralCompletionId,
    required String bookingId,
  });

  /// Generate a new referral code for a user
  Future<ReferralResult<String>> generateReferralCode(String userId);

  /// Get referral stats for a user
  Future<ReferralResult<ReferralStats>> getReferralStats(String userId);

  /// Check if user was referred
  Future<ReferralResult<ReferralCompletion?>> getUserReferredBy(String userId);
}

/// In-memory implementation for development
class InMemoryReferralService implements ReferralService {
  InMemoryReferralService() {
    _initializeSampleData();
  }

  final Map<String, UserReferral> _referrals = {};
  final List<ReferralCompletion> _completions = [];
  final Map<String, String> _userNames = {};

  // Default reward amounts
  static const double defaultReferrerReward = 500;
  static const double defaultRefereeDiscount = 500;

  void _initializeSampleData() {
    // Sample user names for demo
    _userNames['user_1'] = 'Ahmed Rahman';
    _userNames['user_2'] = 'Fatima Khan';
    _userNames['user_3'] = 'Karim Hassan';

    // Sample referral for user_1
    final sampleReferral = UserReferral(
      id: 'ref_1',
      referrerId: 'user_1',
      referralCode: 'AHME1234',
      referrerRewardAmount: defaultReferrerReward,
      refereeDiscountAmount: defaultRefereeDiscount,
      totalReferrals: 3,
      successfulReferrals: 2,
      totalRewardsEarned: 1000,
      isActive: true,
      createdAt: DateTime.now().subtract(const Duration(days: 60)),
    );
    _referrals['user_1'] = sampleReferral;

    // Sample completions
    _completions.addAll([
      ReferralCompletion(
        id: 'comp_1',
        referralId: 'ref_1',
        refereeId: 'user_2',
        signedUpAt: DateTime.now().subtract(const Duration(days: 30)),
        firstBookingId: 'booking_1',
        firstBookingCompletedAt:
            DateTime.now().subtract(const Duration(days: 25)),
        refereeDiscountApplied: true,
        referrerRewardCredited: true,
        referrerRewardCreditedAt:
            DateTime.now().subtract(const Duration(days: 25)),
        status: ReferralStatus.completed,
        refereeName: 'Fatima Khan',
      ),
      ReferralCompletion(
        id: 'comp_2',
        referralId: 'ref_1',
        refereeId: 'user_3',
        signedUpAt: DateTime.now().subtract(const Duration(days: 15)),
        firstBookingId: 'booking_2',
        firstBookingCompletedAt:
            DateTime.now().subtract(const Duration(days: 10)),
        refereeDiscountApplied: true,
        referrerRewardCredited: true,
        referrerRewardCreditedAt:
            DateTime.now().subtract(const Duration(days: 10)),
        status: ReferralStatus.completed,
        refereeName: 'Karim Hassan',
      ),
      ReferralCompletion(
        id: 'comp_3',
        referralId: 'ref_1',
        refereeId: 'user_4',
        signedUpAt: DateTime.now().subtract(const Duration(days: 5)),
        status: ReferralStatus.pending,
        refereeName: 'New User',
      ),
    ]);
  }

  @override
  Future<ReferralResult<UserReferral>> getUserReferral(String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    if (_referrals.containsKey(userId)) {
      return ReferralResult.success(_referrals[userId]!);
    }

    // Create new referral for user
    final code = await _generateCode(userId);
    final referral = UserReferral(
      id: 'ref_${DateTime.now().millisecondsSinceEpoch}',
      referrerId: userId,
      referralCode: code,
      referrerRewardAmount: defaultReferrerReward,
      refereeDiscountAmount: defaultRefereeDiscount,
      createdAt: DateTime.now(),
    );

    _referrals[userId] = referral;
    return ReferralResult.success(referral);
  }

  @override
  Future<ReferralResult<List<ReferralCompletion>>> getReferralCompletions(
      String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final referral = _referrals[userId];
    if (referral == null) {
      return const ReferralResult.success([]);
    }

    final completions = _completions
        .where((c) => c.referralId == referral.id)
        .toList()
      ..sort((a, b) => b.signedUpAt.compareTo(a.signedUpAt));

    return ReferralResult.success(completions);
  }

  @override
  Future<ReferralResult<ReferralCodeValidation>> validateReferralCode(
      String code) async {
    await Future.delayed(const Duration(milliseconds: 150));

    final cleanCode = code.trim().toUpperCase();

    if (cleanCode.isEmpty) {
      return ReferralResult.success(
        ReferralCodeValidation.invalid('Please enter a referral code'),
      );
    }

    // Find referral by code
    final referral = _referrals.values.cast<UserReferral?>().firstWhere(
          (r) => r?.referralCode.toUpperCase() == cleanCode,
          orElse: () => null,
        );

    if (referral == null) {
      return ReferralResult.success(
        ReferralCodeValidation.invalid('Invalid referral code'),
      );
    }

    if (!referral.isActive) {
      return ReferralResult.success(
        ReferralCodeValidation.invalid(
            'This referral code is no longer active'),
      );
    }

    final referrerName = _userNames[referral.referrerId] ?? 'A friend';

    return ReferralResult.success(
      ReferralCodeValidation.valid(
        referral: referral,
        referrerName: referrerName,
        discountAmount: referral.refereeDiscountAmount,
      ),
    );
  }

  @override
  Future<ReferralResult<ReferralCompletion>> applyReferralCode({
    required String refereeId,
    required String referralCode,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    // Validate code first
    final validation = await validateReferralCode(referralCode);
    if (validation.isFailure) {
      return ReferralResult.failure(validation.error!);
    }

    final validationResult = validation.data!;
    if (!validationResult.isValid) {
      return ReferralResult.failure(validationResult.errorMessage!);
    }

    final referral = validationResult.referral!;

    // Check if user was already referred
    final existingCompletion =
        _completions.cast<ReferralCompletion?>().firstWhere(
              (c) => c?.refereeId == refereeId,
              orElse: () => null,
            );

    if (existingCompletion != null) {
      return const ReferralResult.failure(
        'You have already used a referral code',
        'ALREADY_REFERRED',
      );
    }

    // Check if user is referring themselves
    if (referral.referrerId == refereeId) {
      return const ReferralResult.failure(
        'You cannot use your own referral code',
        'SELF_REFERRAL',
      );
    }

    // Create completion
    final completion = ReferralCompletion(
      id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
      referralId: referral.id,
      refereeId: refereeId,
      signedUpAt: DateTime.now(),
      status: ReferralStatus.pending,
      createdAt: DateTime.now(),
    );

    _completions.add(completion);

    // Update referral stats
    _referrals[referral.referrerId] = referral.copyWith(
      totalReferrals: referral.totalReferrals + 1,
    );

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║              REFERRAL CODE APPLIED                           ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print('║ Referee: $refereeId');
    print('║ Referrer: ${referral.referrerId}');
    print('║ Code: ${referral.referralCode}');
    print('║ Discount: ৳${referral.refereeDiscountAmount}');
    print('╚══════════════════════════════════════════════════════════════╝');

    return ReferralResult.success(completion);
  }

  @override
  Future<ReferralResult<void>> markDiscountUsed(
      String referralCompletionId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final index = _completions.indexWhere((c) => c.id == referralCompletionId);
    if (index == -1) {
      return const ReferralResult.failure('Referral completion not found');
    }

    _completions[index] = _completions[index].copyWith(
      refereeDiscountApplied: true,
      status: ReferralStatus.discountUsed,
      updatedAt: DateTime.now(),
    );

    return const ReferralResult.success(null);
  }

  @override
  Future<ReferralResult<void>> completeReferral({
    required String referralCompletionId,
    required String bookingId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final index = _completions.indexWhere((c) => c.id == referralCompletionId);
    if (index == -1) {
      return const ReferralResult.failure('Referral completion not found');
    }

    final completion = _completions[index];

    // Update completion
    _completions[index] = completion.copyWith(
      firstBookingId: bookingId,
      firstBookingCompletedAt: DateTime.now(),
      referrerRewardCredited: true,
      referrerRewardCreditedAt: DateTime.now(),
      status: ReferralStatus.completed,
      updatedAt: DateTime.now(),
    );

    // Update referral stats
    final referral = _referrals.values.firstWhere(
      (r) => r.id == completion.referralId,
    );

    _referrals[referral.referrerId] = referral.copyWith(
      successfulReferrals: referral.successfulReferrals + 1,
      totalRewardsEarned:
          referral.totalRewardsEarned + referral.referrerRewardAmount,
      updatedAt: DateTime.now(),
    );

    print('╔══════════════════════════════════════════════════════════════╗');
    print('║              REFERRAL COMPLETED                              ║');
    print('╠══════════════════════════════════════════════════════════════╣');
    print(
        '║ Referrer ${referral.referrerId} earned ৳${referral.referrerRewardAmount}');
    print('║ Booking ID: $bookingId');
    print('╚══════════════════════════════════════════════════════════════╝');

    return const ReferralResult.success(null);
  }

  @override
  Future<ReferralResult<String>> generateReferralCode(String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final code = await _generateCode(userId);

    // Update existing referral if exists
    if (_referrals.containsKey(userId)) {
      _referrals[userId] = _referrals[userId]!.copyWith(
        referralCode: code,
        updatedAt: DateTime.now(),
      );
    }

    return ReferralResult.success(code);
  }

  @override
  Future<ReferralResult<ReferralStats>> getReferralStats(String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final referral = _referrals[userId];
    if (referral == null) {
      return ReferralResult.success(ReferralStats.empty());
    }

    final completions =
        _completions.where((c) => c.referralId == referral.id).toList();

    return ReferralResult.success(
      ReferralStats.fromReferral(referral, completions),
    );
  }

  @override
  Future<ReferralResult<ReferralCompletion?>> getUserReferredBy(
      String userId) async {
    await Future.delayed(const Duration(milliseconds: 150));

    final completion = _completions.cast<ReferralCompletion?>().firstWhere(
          (c) => c?.refereeId == userId,
          orElse: () => null,
        );

    return ReferralResult.success(completion);
  }

  Future<String> _generateCode(String userId) async {
    final userName = _userNames[userId] ?? 'USER';
    final namePart = userName
        .replaceAll(RegExp(r'[^a-zA-Z]'), '')
        .toUpperCase()
        .substring(0, min(4, userName.length));

    final random = Random();
    final randomPart = String.fromCharCodes(
      List.generate(4, (_) => random.nextInt(10) + 48), // 0-9
    );

    return '$namePart$randomPart';
  }

  /// For testing: set user name
  void setUserName(String userId, String name) {
    _userNames[userId] = name;
  }

  /// For testing: get all referrals
  List<UserReferral> get allReferrals => _referrals.values.toList();

  /// For testing: get all completions
  List<ReferralCompletion> get allCompletions => List.from(_completions);
}
