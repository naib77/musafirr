import 'package:flutter/foundation.dart';

/// Status of a referral
enum ReferralStatus {
  /// Referee signed up but hasn't booked
  pending,

  /// Referee used their discount
  discountUsed,

  /// Referee completed first booking, rewards credited
  completed,

  /// Referral expired or invalidated
  expired,
}

extension ReferralStatusExtension on ReferralStatus {
  String get displayName {
    switch (this) {
      case ReferralStatus.pending:
        return 'Pending';
      case ReferralStatus.discountUsed:
        return 'Discount Used';
      case ReferralStatus.completed:
        return 'Completed';
      case ReferralStatus.expired:
        return 'Expired';
    }
  }

  String get databaseValue {
    switch (this) {
      case ReferralStatus.pending:
        return 'pending';
      case ReferralStatus.discountUsed:
        return 'discount_used';
      case ReferralStatus.completed:
        return 'completed';
      case ReferralStatus.expired:
        return 'expired';
    }
  }

  static ReferralStatus fromDatabase(String value) {
    switch (value) {
      case 'pending':
        return ReferralStatus.pending;
      case 'discount_used':
        return ReferralStatus.discountUsed;
      case 'completed':
        return ReferralStatus.completed;
      case 'expired':
        return ReferralStatus.expired;
      default:
        return ReferralStatus.pending;
    }
  }
}

/// User's referral program information
@immutable
class UserReferral {
  const UserReferral({
    required this.id,
    required this.referrerId,
    required this.referralCode,
    required this.referrerRewardAmount,
    required this.refereeDiscountAmount,
    this.totalReferrals = 0,
    this.successfulReferrals = 0,
    this.totalRewardsEarned = 0,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String referrerId;
  final String referralCode;
  final double referrerRewardAmount;
  final double refereeDiscountAmount;
  final int totalReferrals;
  final int successfulReferrals;
  final double totalRewardsEarned;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Pending referrals (signed up but not completed)
  int get pendingReferrals => totalReferrals - successfulReferrals;

  /// Conversion rate
  double get conversionRate {
    if (totalReferrals == 0) return 0;
    return (successfulReferrals / totalReferrals) * 100;
  }

  /// Shareable referral link
  String get shareLink => 'https://musaafir.app/ref/$referralCode';

  /// Share message
  String get shareMessage =>
      'Join Musaafir and get ৳${refereeDiscountAmount.toStringAsFixed(0)} off your first booking! Use my code: $referralCode or sign up here: $shareLink';

  factory UserReferral.fromJson(Map<String, dynamic> json) {
    return UserReferral(
      id: json['id'] as String,
      referrerId: json['referrer_id'] as String,
      referralCode: json['referral_code'] as String,
      referrerRewardAmount:
          (json['referrer_reward_amount'] as num?)?.toDouble() ?? 500,
      refereeDiscountAmount:
          (json['referee_discount_amount'] as num?)?.toDouble() ?? 500,
      totalReferrals: json['total_referrals'] as int? ?? 0,
      successfulReferrals: json['successful_referrals'] as int? ?? 0,
      totalRewardsEarned:
          (json['total_rewards_earned'] as num?)?.toDouble() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'referrer_id': referrerId,
      'referral_code': referralCode,
      'referrer_reward_amount': referrerRewardAmount,
      'referee_discount_amount': refereeDiscountAmount,
      'total_referrals': totalReferrals,
      'successful_referrals': successfulReferrals,
      'total_rewards_earned': totalRewardsEarned,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  UserReferral copyWith({
    String? id,
    String? referrerId,
    String? referralCode,
    double? referrerRewardAmount,
    double? refereeDiscountAmount,
    int? totalReferrals,
    int? successfulReferrals,
    double? totalRewardsEarned,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserReferral(
      id: id ?? this.id,
      referrerId: referrerId ?? this.referrerId,
      referralCode: referralCode ?? this.referralCode,
      referrerRewardAmount: referrerRewardAmount ?? this.referrerRewardAmount,
      refereeDiscountAmount:
          refereeDiscountAmount ?? this.refereeDiscountAmount,
      totalReferrals: totalReferrals ?? this.totalReferrals,
      successfulReferrals: successfulReferrals ?? this.successfulReferrals,
      totalRewardsEarned: totalRewardsEarned ?? this.totalRewardsEarned,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserReferral &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A single referral completion record
@immutable
class ReferralCompletion {
  const ReferralCompletion({
    required this.id,
    required this.referralId,
    required this.refereeId,
    required this.signedUpAt,
    this.firstBookingId,
    this.firstBookingCompletedAt,
    this.refereeDiscountApplied = false,
    this.referrerRewardCredited = false,
    this.referrerRewardCreditedAt,
    this.status = ReferralStatus.pending,
    this.refereeName,
    this.refereeAvatarUrl,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String referralId;
  final String refereeId;
  final DateTime signedUpAt;
  final String? firstBookingId;
  final DateTime? firstBookingCompletedAt;
  final bool refereeDiscountApplied;
  final bool referrerRewardCredited;
  final DateTime? referrerRewardCreditedAt;
  final ReferralStatus status;

  // Populated from join
  final String? refereeName;
  final String? refereeAvatarUrl;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Days since signup
  int get daysSinceSignup => DateTime.now().difference(signedUpAt).inDays;

  /// Whether the referral is still pending
  bool get isPending => status == ReferralStatus.pending;

  /// Whether the referral is complete
  bool get isComplete => status == ReferralStatus.completed;

  factory ReferralCompletion.fromJson(Map<String, dynamic> json) {
    return ReferralCompletion(
      id: json['id'] as String,
      referralId: json['referral_id'] as String,
      refereeId: json['referee_id'] as String,
      signedUpAt: DateTime.parse(json['signed_up_at'] as String),
      firstBookingId: json['first_booking_id'] as String?,
      firstBookingCompletedAt: json['first_booking_completed_at'] != null
          ? DateTime.parse(json['first_booking_completed_at'] as String)
          : null,
      refereeDiscountApplied:
          json['referee_discount_applied'] as bool? ?? false,
      referrerRewardCredited:
          json['referrer_reward_credited'] as bool? ?? false,
      referrerRewardCreditedAt: json['referrer_reward_credited_at'] != null
          ? DateTime.parse(json['referrer_reward_credited_at'] as String)
          : null,
      status: ReferralStatusExtension.fromDatabase(
          json['status'] as String? ?? 'pending'),
      refereeName: json['referee']?['full_name'] as String? ??
          json['referee_name'] as String?,
      refereeAvatarUrl: json['referee']?['avatar_url'] as String? ??
          json['referee_avatar_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'referral_id': referralId,
      'referee_id': refereeId,
      'signed_up_at': signedUpAt.toIso8601String(),
      'first_booking_id': firstBookingId,
      'first_booking_completed_at': firstBookingCompletedAt?.toIso8601String(),
      'referee_discount_applied': refereeDiscountApplied,
      'referrer_reward_credited': referrerRewardCredited,
      'referrer_reward_credited_at':
          referrerRewardCreditedAt?.toIso8601String(),
      'status': status.databaseValue,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  ReferralCompletion copyWith({
    String? id,
    String? referralId,
    String? refereeId,
    DateTime? signedUpAt,
    String? firstBookingId,
    DateTime? firstBookingCompletedAt,
    bool? refereeDiscountApplied,
    bool? referrerRewardCredited,
    DateTime? referrerRewardCreditedAt,
    ReferralStatus? status,
    String? refereeName,
    String? refereeAvatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReferralCompletion(
      id: id ?? this.id,
      referralId: referralId ?? this.referralId,
      refereeId: refereeId ?? this.refereeId,
      signedUpAt: signedUpAt ?? this.signedUpAt,
      firstBookingId: firstBookingId ?? this.firstBookingId,
      firstBookingCompletedAt:
          firstBookingCompletedAt ?? this.firstBookingCompletedAt,
      refereeDiscountApplied:
          refereeDiscountApplied ?? this.refereeDiscountApplied,
      referrerRewardCredited:
          referrerRewardCredited ?? this.referrerRewardCredited,
      referrerRewardCreditedAt:
          referrerRewardCreditedAt ?? this.referrerRewardCreditedAt,
      status: status ?? this.status,
      refereeName: refereeName ?? this.refereeName,
      refereeAvatarUrl: refereeAvatarUrl ?? this.refereeAvatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReferralCompletion &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Summary statistics for referrals
@immutable
class ReferralStats {
  const ReferralStats({
    required this.totalReferrals,
    required this.pendingReferrals,
    required this.completedReferrals,
    required this.totalEarnings,
    required this.pendingEarnings,
  });

  final int totalReferrals;
  final int pendingReferrals;
  final int completedReferrals;
  final double totalEarnings;
  final double pendingEarnings;

  /// Conversion rate percentage
  double get conversionRate {
    if (totalReferrals == 0) return 0;
    return (completedReferrals / totalReferrals) * 100;
  }

  factory ReferralStats.empty() {
    return const ReferralStats(
      totalReferrals: 0,
      pendingReferrals: 0,
      completedReferrals: 0,
      totalEarnings: 0,
      pendingEarnings: 0,
    );
  }

  factory ReferralStats.fromReferral(
    UserReferral referral,
    List<ReferralCompletion> completions,
  ) {
    final pending =
        completions.where((c) => c.status == ReferralStatus.pending).length;
    final completed =
        completions.where((c) => c.status == ReferralStatus.completed).length;
    final pendingEarnings = pending * referral.referrerRewardAmount;

    return ReferralStats(
      totalReferrals: referral.totalReferrals,
      pendingReferrals: pending,
      completedReferrals: completed,
      totalEarnings: referral.totalRewardsEarned,
      pendingEarnings: pendingEarnings,
    );
  }
}

/// Referral validation result
class ReferralCodeValidation {
  const ReferralCodeValidation._({
    required this.isValid,
    this.referral,
    this.referrerName,
    this.discountAmount,
    this.errorMessage,
  });

  factory ReferralCodeValidation.valid({
    required UserReferral referral,
    required String referrerName,
    required double discountAmount,
  }) {
    return ReferralCodeValidation._(
      isValid: true,
      referral: referral,
      referrerName: referrerName,
      discountAmount: discountAmount,
    );
  }

  factory ReferralCodeValidation.invalid(String errorMessage) {
    return ReferralCodeValidation._(
      isValid: false,
      errorMessage: errorMessage,
    );
  }

  final bool isValid;
  final UserReferral? referral;
  final String? referrerName;
  final double? discountAmount;
  final String? errorMessage;

  String get displayMessage {
    if (isValid && referrerName != null && discountAmount != null) {
      return 'You\'ll get ৳${discountAmount!.toStringAsFixed(0)} off! Referred by $referrerName';
    }
    return errorMessage ?? 'Invalid referral code';
  }
}
