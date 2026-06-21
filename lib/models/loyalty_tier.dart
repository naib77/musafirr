import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Loyalty tier levels
enum LoyaltyTierLevel {
  bronze,
  silver,
  gold,
  platinum,
}

extension LoyaltyTierLevelExtension on LoyaltyTierLevel {
  int get level {
    switch (this) {
      case LoyaltyTierLevel.bronze:
        return 1;
      case LoyaltyTierLevel.silver:
        return 2;
      case LoyaltyTierLevel.gold:
        return 3;
      case LoyaltyTierLevel.platinum:
        return 4;
    }
  }

  String get displayName {
    switch (this) {
      case LoyaltyTierLevel.bronze:
        return 'Bronze';
      case LoyaltyTierLevel.silver:
        return 'Silver';
      case LoyaltyTierLevel.gold:
        return 'Gold';
      case LoyaltyTierLevel.platinum:
        return 'Platinum';
    }
  }

  Color get color {
    switch (this) {
      case LoyaltyTierLevel.bronze:
        return const Color(0xFFCD7F32);
      case LoyaltyTierLevel.silver:
        return const Color(0xFFC0C0C0);
      case LoyaltyTierLevel.gold:
        return const Color(0xFFFFD700);
      case LoyaltyTierLevel.platinum:
        return const Color(0xFFE5E4E2);
    }
  }

  IconData get icon {
    switch (this) {
      case LoyaltyTierLevel.bronze:
        return Icons.star_border;
      case LoyaltyTierLevel.silver:
        return Icons.star_half;
      case LoyaltyTierLevel.gold:
        return Icons.star;
      case LoyaltyTierLevel.platinum:
        return Icons.workspace_premium;
    }
  }

  static LoyaltyTierLevel fromLevel(int level) {
    switch (level) {
      case 1:
        return LoyaltyTierLevel.bronze;
      case 2:
        return LoyaltyTierLevel.silver;
      case 3:
        return LoyaltyTierLevel.gold;
      case 4:
        return LoyaltyTierLevel.platinum;
      default:
        return LoyaltyTierLevel.bronze;
    }
  }

  static LoyaltyTierLevel fromName(String name) {
    switch (name.toLowerCase()) {
      case 'bronze':
        return LoyaltyTierLevel.bronze;
      case 'silver':
        return LoyaltyTierLevel.silver;
      case 'gold':
        return LoyaltyTierLevel.gold;
      case 'platinum':
        return LoyaltyTierLevel.platinum;
      default:
        return LoyaltyTierLevel.bronze;
    }
  }
}

/// Loyalty tier definition
@immutable
class LoyaltyTier {
  const LoyaltyTier({
    required this.id,
    required this.name,
    required this.level,
    this.minBookings = 0,
    this.minNightsStayed = 0,
    this.minTotalSpent = 0,
    this.discountPercentage = 0,
    this.prioritySupport = false,
    this.freeCancellationWindow = 24,
    this.earlyAccessHours = 0,
    this.badgeColor,
    this.iconName,
    this.metadata,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final int level;

  // Requirements
  final int minBookings;
  final int minNightsStayed;
  final double minTotalSpent;

  // Benefits
  final double discountPercentage;
  final bool prioritySupport;
  final int freeCancellationWindow; // Hours
  final int earlyAccessHours;

  // Visual
  final String? badgeColor;
  final String? iconName;

  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Get the tier level enum
  LoyaltyTierLevel get tierLevel => LoyaltyTierLevelExtension.fromLevel(level);

  /// Get color from badge color or default
  Color get color {
    if (badgeColor != null) {
      try {
        return Color(
            int.parse(badgeColor!.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return tierLevel.color;
  }

  /// Get icon data
  IconData get icon {
    if (iconName != null) {
      switch (iconName) {
        case 'star_border':
          return Icons.star_border;
        case 'star_half':
          return Icons.star_half;
        case 'star':
          return Icons.star;
        case 'workspace_premium':
          return Icons.workspace_premium;
      }
    }
    return tierLevel.icon;
  }

  /// Get benefits as a list of strings
  List<String> get benefitsList {
    final benefits = <String>[];

    if (discountPercentage > 0) {
      benefits.add('${discountPercentage.toStringAsFixed(0)}% discount on all bookings');
    }

    if (prioritySupport) {
      benefits.add('Priority customer support');
    }

    if (freeCancellationWindow > 24) {
      final hours = freeCancellationWindow;
      if (hours >= 168) {
        benefits.add('Free cancellation up to ${(hours / 24).round()} days before');
      } else if (hours >= 24) {
        benefits.add('Free cancellation up to ${(hours / 24).round()} days before');
      } else {
        benefits.add('Free cancellation up to $hours hours before');
      }
    }

    if (earlyAccessHours > 0) {
      if (earlyAccessHours >= 24) {
        benefits.add('${(earlyAccessHours / 24).round()}-day early access to new listings');
      } else {
        benefits.add('$earlyAccessHours-hour early access to new listings');
      }
    }

    return benefits;
  }

  factory LoyaltyTier.fromJson(Map<String, dynamic> json) {
    return LoyaltyTier(
      id: json['id'] as String,
      name: json['name'] as String,
      level: json['level'] as int,
      minBookings: json['min_bookings'] as int? ?? 0,
      minNightsStayed: json['min_nights_stayed'] as int? ?? 0,
      minTotalSpent: (json['min_total_spent'] as num?)?.toDouble() ?? 0,
      discountPercentage:
          (json['discount_percentage'] as num?)?.toDouble() ?? 0,
      prioritySupport: json['priority_support'] as bool? ?? false,
      freeCancellationWindow:
          json['free_cancellation_window'] as int? ?? 24,
      earlyAccessHours: json['early_access_hours'] as int? ?? 0,
      badgeColor: json['badge_color'] as String?,
      iconName: json['icon_name'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
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
      'name': name,
      'level': level,
      'min_bookings': minBookings,
      'min_nights_stayed': minNightsStayed,
      'min_total_spent': minTotalSpent,
      'discount_percentage': discountPercentage,
      'priority_support': prioritySupport,
      'free_cancellation_window': freeCancellationWindow,
      'early_access_hours': earlyAccessHours,
      'badge_color': badgeColor,
      'icon_name': iconName,
      'metadata': metadata,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoyaltyTier &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// User's loyalty status
@immutable
class UserLoyalty {
  const UserLoyalty({
    required this.id,
    required this.userId,
    this.currentTier,
    this.currentTierId,
    this.totalBookings = 0,
    this.totalNightsStayed = 0,
    this.totalAmountSpent = 0,
    this.loyaltyPoints = 0,
    this.creditsBalance = 0,
    this.tierUpgradedAt,
    this.previousTierId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userId;
  final LoyaltyTier? currentTier;
  final String? currentTierId;
  final int totalBookings;
  final int totalNightsStayed;
  final double totalAmountSpent;
  final int loyaltyPoints;
  final double creditsBalance;
  final DateTime? tierUpgradedAt;
  final String? previousTierId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Get tier level (defaults to Bronze if no tier)
  LoyaltyTierLevel get tierLevel =>
      currentTier?.tierLevel ?? LoyaltyTierLevel.bronze;

  /// Get tier name
  String get tierName => currentTier?.name ?? 'Bronze';

  /// Get discount percentage
  double get discountPercentage => currentTier?.discountPercentage ?? 0;

  /// Check if user was recently upgraded
  bool get wasRecentlyUpgraded {
    if (tierUpgradedAt == null) return false;
    return DateTime.now().difference(tierUpgradedAt!).inDays <= 7;
  }

  factory UserLoyalty.fromJson(Map<String, dynamic> json) {
    return UserLoyalty(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      currentTier: json['current_tier'] != null
          ? LoyaltyTier.fromJson(json['current_tier'] as Map<String, dynamic>)
          : (json['loyalty_tier'] != null
              ? LoyaltyTier.fromJson(
                  json['loyalty_tier'] as Map<String, dynamic>)
              : null),
      currentTierId: json['current_tier_id'] as String?,
      totalBookings: json['total_bookings'] as int? ?? 0,
      totalNightsStayed: json['total_nights_stayed'] as int? ?? 0,
      totalAmountSpent:
          (json['total_amount_spent'] as num?)?.toDouble() ?? 0,
      loyaltyPoints: json['loyalty_points'] as int? ?? 0,
      creditsBalance: (json['credits_balance'] as num?)?.toDouble() ?? 0,
      tierUpgradedAt: json['tier_upgraded_at'] != null
          ? DateTime.parse(json['tier_upgraded_at'] as String)
          : null,
      previousTierId: json['previous_tier_id'] as String?,
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
      'user_id': userId,
      'current_tier_id': currentTierId,
      'total_bookings': totalBookings,
      'total_nights_stayed': totalNightsStayed,
      'total_amount_spent': totalAmountSpent,
      'loyalty_points': loyaltyPoints,
      'credits_balance': creditsBalance,
      'tier_upgraded_at': tierUpgradedAt?.toIso8601String(),
      'previous_tier_id': previousTierId,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  UserLoyalty copyWith({
    String? id,
    String? userId,
    LoyaltyTier? currentTier,
    String? currentTierId,
    int? totalBookings,
    int? totalNightsStayed,
    double? totalAmountSpent,
    int? loyaltyPoints,
    double? creditsBalance,
    DateTime? tierUpgradedAt,
    String? previousTierId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserLoyalty(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      currentTier: currentTier ?? this.currentTier,
      currentTierId: currentTierId ?? this.currentTierId,
      totalBookings: totalBookings ?? this.totalBookings,
      totalNightsStayed: totalNightsStayed ?? this.totalNightsStayed,
      totalAmountSpent: totalAmountSpent ?? this.totalAmountSpent,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      creditsBalance: creditsBalance ?? this.creditsBalance,
      tierUpgradedAt: tierUpgradedAt ?? this.tierUpgradedAt,
      previousTierId: previousTierId ?? this.previousTierId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserLoyalty &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Progress towards next tier
@immutable
class TierProgress {
  const TierProgress({
    required this.currentTier,
    required this.nextTier,
    required this.bookingsProgress,
    required this.bookingsRequired,
    required this.nightsProgress,
    required this.nightsRequired,
    required this.spentProgress,
    required this.spentRequired,
  });

  final LoyaltyTier currentTier;
  final LoyaltyTier? nextTier;
  final int bookingsProgress;
  final int bookingsRequired;
  final int nightsProgress;
  final int nightsRequired;
  final double spentProgress;
  final double spentRequired;

  /// Whether there's a next tier to achieve
  bool get hasNextTier => nextTier != null;

  /// Overall progress percentage (0-100)
  double get overallProgress {
    if (!hasNextTier) return 100;

    final bookingPercent = bookingsRequired > 0
        ? (bookingsProgress / bookingsRequired * 100).clamp(0, 100)
        : 100;
    final nightsPercent = nightsRequired > 0
        ? (nightsProgress / nightsRequired * 100).clamp(0, 100)
        : 100;
    final spentPercent = spentRequired > 0
        ? (spentProgress / spentRequired * 100).clamp(0, 100)
        : 100;

    // Use the minimum since all requirements must be met
    return [bookingPercent, nightsPercent, spentPercent]
        .reduce((a, b) => a < b ? a : b)
        .toDouble();
  }

  /// Bookings progress percentage
  double get bookingsProgressPercent {
    if (bookingsRequired == 0) return 100;
    return (bookingsProgress / bookingsRequired * 100).clamp(0, 100);
  }

  /// Nights progress percentage
  double get nightsProgressPercent {
    if (nightsRequired == 0) return 100;
    return (nightsProgress / nightsRequired * 100).clamp(0, 100);
  }

  /// Spent progress percentage
  double get spentProgressPercent {
    if (spentRequired == 0) return 100;
    return (spentProgress / spentRequired * 100).clamp(0, 100);
  }

  /// Bookings remaining
  int get bookingsRemaining => (bookingsRequired - bookingsProgress).clamp(0, bookingsRequired);

  /// Nights remaining
  int get nightsRemaining => (nightsRequired - nightsProgress).clamp(0, nightsRequired);

  /// Amount remaining to spend
  double get spentRemaining => (spentRequired - spentProgress).clamp(0, spentRequired);

  factory TierProgress.fromUserLoyalty(
    UserLoyalty loyalty,
    List<LoyaltyTier> allTiers,
  ) {
    final currentTier = loyalty.currentTier ??
        allTiers.firstWhere(
          (t) => t.level == 1,
          orElse: () => allTiers.first,
        );

    final nextTier = allTiers
        .where((t) => t.level > currentTier.level)
        .fold<LoyaltyTier?>(null, (prev, t) {
      if (prev == null || t.level < prev.level) return t;
      return prev;
    });

    return TierProgress(
      currentTier: currentTier,
      nextTier: nextTier,
      bookingsProgress: loyalty.totalBookings,
      bookingsRequired: nextTier?.minBookings ?? currentTier.minBookings,
      nightsProgress: loyalty.totalNightsStayed,
      nightsRequired: nextTier?.minNightsStayed ?? currentTier.minNightsStayed,
      spentProgress: loyalty.totalAmountSpent,
      spentRequired: nextTier?.minTotalSpent ?? currentTier.minTotalSpent,
    );
  }
}
