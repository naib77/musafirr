import 'package:flutter/foundation.dart';

/// Discount type determines how the value is applied
enum DiscountType {
  /// Percentage off the total (0-100)
  percentage,

  /// Fixed amount off in BDT
  fixedAmount,

  /// Free nights (e.g., stay 7 pay 5)
  freeNights,
}

extension DiscountTypeExtension on DiscountType {
  String get displayName {
    switch (this) {
      case DiscountType.percentage:
        return 'Percentage';
      case DiscountType.fixedAmount:
        return 'Fixed Amount';
      case DiscountType.freeNights:
        return 'Free Nights';
    }
  }

  String get databaseValue {
    switch (this) {
      case DiscountType.percentage:
        return 'percentage';
      case DiscountType.fixedAmount:
        return 'fixed_amount';
      case DiscountType.freeNights:
        return 'free_nights';
    }
  }

  static DiscountType fromDatabase(String value) {
    switch (value) {
      case 'percentage':
        return DiscountType.percentage;
      case 'fixed_amount':
        return DiscountType.fixedAmount;
      case 'free_nights':
        return DiscountType.freeNights;
      default:
        return DiscountType.percentage;
    }
  }
}

/// Category of discount (who created/owns it)
enum DiscountCategory {
  /// Platform-wide promotions
  platform,

  /// Host-created discounts
  host,

  /// Referral rewards
  referral,

  /// Loyalty tier benefits
  loyalty,

  /// First-time user discount
  firstBooking,

  /// Seasonal campaigns
  seasonal,

  /// Time-limited flash sales
  flashSale,
}

extension DiscountCategoryExtension on DiscountCategory {
  String get displayName {
    switch (this) {
      case DiscountCategory.platform:
        return 'Platform';
      case DiscountCategory.host:
        return 'Host';
      case DiscountCategory.referral:
        return 'Referral';
      case DiscountCategory.loyalty:
        return 'Loyalty';
      case DiscountCategory.firstBooking:
        return 'First Booking';
      case DiscountCategory.seasonal:
        return 'Seasonal';
      case DiscountCategory.flashSale:
        return 'Flash Sale';
    }
  }

  String get databaseValue {
    switch (this) {
      case DiscountCategory.platform:
        return 'platform';
      case DiscountCategory.host:
        return 'host';
      case DiscountCategory.referral:
        return 'referral';
      case DiscountCategory.loyalty:
        return 'loyalty';
      case DiscountCategory.firstBooking:
        return 'first_booking';
      case DiscountCategory.seasonal:
        return 'seasonal';
      case DiscountCategory.flashSale:
        return 'flash_sale';
    }
  }

  static DiscountCategory fromDatabase(String value) {
    switch (value) {
      case 'platform':
        return DiscountCategory.platform;
      case 'host':
        return DiscountCategory.host;
      case 'referral':
        return DiscountCategory.referral;
      case 'loyalty':
        return DiscountCategory.loyalty;
      case 'first_booking':
        return DiscountCategory.firstBooking;
      case 'seasonal':
        return DiscountCategory.seasonal;
      case 'flash_sale':
        return DiscountCategory.flashSale;
      default:
        return DiscountCategory.platform;
    }
  }
}

/// Discount status
enum DiscountStatus {
  /// Not yet active
  draft,

  /// Currently active
  active,

  /// Temporarily paused
  paused,

  /// Past end date
  expired,

  /// Usage limit reached
  exhausted,
}

extension DiscountStatusExtension on DiscountStatus {
  String get displayName {
    switch (this) {
      case DiscountStatus.draft:
        return 'Draft';
      case DiscountStatus.active:
        return 'Active';
      case DiscountStatus.paused:
        return 'Paused';
      case DiscountStatus.expired:
        return 'Expired';
      case DiscountStatus.exhausted:
        return 'Exhausted';
    }
  }

  String get databaseValue {
    switch (this) {
      case DiscountStatus.draft:
        return 'draft';
      case DiscountStatus.active:
        return 'active';
      case DiscountStatus.paused:
        return 'paused';
      case DiscountStatus.expired:
        return 'expired';
      case DiscountStatus.exhausted:
        return 'exhausted';
    }
  }

  static DiscountStatus fromDatabase(String value) {
    switch (value) {
      case 'draft':
        return DiscountStatus.draft;
      case 'active':
        return DiscountStatus.active;
      case 'paused':
        return DiscountStatus.paused;
      case 'expired':
        return DiscountStatus.expired;
      case 'exhausted':
        return DiscountStatus.exhausted;
      default:
        return DiscountStatus.draft;
    }
  }
}

/// Stacking behavior for combining discounts
enum StackingBehavior {
  /// Can combine with other discounts
  stackable,

  /// Cannot combine with others
  exclusive,

  /// Only apply if best discount
  bestOnly,
}

extension StackingBehaviorExtension on StackingBehavior {
  String get displayName {
    switch (this) {
      case StackingBehavior.stackable:
        return 'Stackable';
      case StackingBehavior.exclusive:
        return 'Exclusive';
      case StackingBehavior.bestOnly:
        return 'Best Only';
    }
  }

  String get databaseValue {
    switch (this) {
      case StackingBehavior.stackable:
        return 'stackable';
      case StackingBehavior.exclusive:
        return 'exclusive';
      case StackingBehavior.bestOnly:
        return 'best_only';
    }
  }

  static StackingBehavior fromDatabase(String value) {
    switch (value) {
      case 'stackable':
        return StackingBehavior.stackable;
      case 'exclusive':
        return StackingBehavior.exclusive;
      case 'best_only':
        return StackingBehavior.bestOnly;
      default:
        return StackingBehavior.bestOnly;
    }
  }
}

/// Free nights configuration
@immutable
class FreeNightsConfig {
  const FreeNightsConfig({
    required this.stayNights,
    required this.payNights,
  });

  /// Minimum nights to stay
  final int stayNights;

  /// Number of nights to pay for
  final int payNights;

  /// Number of free nights
  int get freeNights => stayNights - payNights;

  factory FreeNightsConfig.fromJson(Map<String, dynamic> json) {
    return FreeNightsConfig(
      stayNights: json['stay'] as int? ?? 7,
      payNights: json['pay'] as int? ?? 5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stay': stayNights,
      'pay': payNights,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreeNightsConfig &&
          runtimeType == other.runtimeType &&
          stayNights == other.stayNights &&
          payNights == other.payNights;

  @override
  int get hashCode => stayNights.hashCode ^ payNights.hashCode;
}

/// Main Discount model
@immutable
class Discount {
  const Discount({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    required this.status,
    required this.value,
    required this.startsAt,
    this.code,
    this.description,
    this.maxDiscountAmount,
    this.minBookingAmount = 0,
    this.freeNightsConfig,
    this.endsAt,
    this.totalUsageLimit,
    this.perUserLimit = 1,
    this.currentUsageCount = 0,
    this.eligibleUserIds,
    this.eligibleListingIds,
    this.eligibleHostIds,
    this.minNights = 1,
    this.maxNights,
    this.newUsersOnly = false,
    this.firstBookingOnly = false,
    this.bookingStartDate,
    this.bookingEndDate,
    this.checkInStartDate,
    this.checkInEndDate,
    this.allowedCheckInDays,
    this.stackingBehavior = StackingBehavior.bestOnly,
    this.stackableWithCategories,
    this.priority = 100,
    this.createdBy,
    this.hostId,
    this.metadata,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String? code;
  final String name;
  final String? description;
  final DiscountType type;
  final DiscountCategory category;
  final DiscountStatus status;

  /// Value: percentage (0-100) or fixed amount in BDT
  final double value;

  /// Maximum discount for percentage type
  final double? maxDiscountAmount;

  /// Minimum booking amount required
  final double minBookingAmount;

  /// Configuration for free nights type
  final FreeNightsConfig? freeNightsConfig;

  /// Validity dates
  final DateTime startsAt;
  final DateTime? endsAt;

  /// Usage limits
  final int? totalUsageLimit;
  final int? perUserLimit;
  final int currentUsageCount;

  /// Eligibility restrictions
  final List<String>? eligibleUserIds;
  final List<String>? eligibleListingIds;
  final List<String>? eligibleHostIds;
  final int minNights;
  final int? maxNights;
  final bool newUsersOnly;
  final bool firstBookingOnly;

  /// Date restrictions
  final DateTime? bookingStartDate;
  final DateTime? bookingEndDate;
  final DateTime? checkInStartDate;
  final DateTime? checkInEndDate;

  /// Day of week restrictions (0 = Sunday, 6 = Saturday)
  final List<int>? allowedCheckInDays;

  /// Stacking rules
  final StackingBehavior stackingBehavior;
  final List<DiscountCategory>? stackableWithCategories;
  final int priority;

  /// Ownership
  final String? createdBy;
  final String? hostId;

  /// Additional data
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Check if discount is currently valid (time-wise)
  bool get isCurrentlyValid {
    final now = DateTime.now();
    if (status != DiscountStatus.active) return false;
    if (startsAt.isAfter(now)) return false;
    if (endsAt != null && endsAt!.isBefore(now)) return false;
    return true;
  }

  /// Check if usage limit reached
  bool get isUsageLimitReached {
    if (totalUsageLimit == null) return false;
    return currentUsageCount >= totalUsageLimit!;
  }

  /// Remaining uses
  int? get remainingUses {
    if (totalUsageLimit == null) return null;
    return totalUsageLimit! - currentUsageCount;
  }

  /// Get display value string
  String get displayValue {
    switch (type) {
      case DiscountType.percentage:
        return '${value.toStringAsFixed(0)}%';
      case DiscountType.fixedAmount:
        return '৳${value.toStringAsFixed(0)}';
      case DiscountType.freeNights:
        if (freeNightsConfig != null) {
          return 'Stay ${freeNightsConfig!.stayNights}, Pay ${freeNightsConfig!.payNights}';
        }
        return 'Free Nights';
    }
  }

  /// Get short description for badges
  String get shortDescription {
    switch (type) {
      case DiscountType.percentage:
        return '${value.toStringAsFixed(0)}% OFF';
      case DiscountType.fixedAmount:
        return '৳${value.toStringAsFixed(0)} OFF';
      case DiscountType.freeNights:
        if (freeNightsConfig != null) {
          return '${freeNightsConfig!.freeNights} NIGHTS FREE';
        }
        return 'FREE NIGHTS';
    }
  }

  factory Discount.fromJson(Map<String, dynamic> json) {
    return Discount(
      id: json['id'] as String,
      code: json['code'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      type: DiscountTypeExtension.fromDatabase(json['type'] as String),
      category:
          DiscountCategoryExtension.fromDatabase(json['category'] as String),
      status: DiscountStatusExtension.fromDatabase(
          json['status'] as String? ?? 'draft'),
      value: (json['value'] as num).toDouble(),
      maxDiscountAmount: json['max_discount_amount'] != null
          ? (json['max_discount_amount'] as num).toDouble()
          : null,
      minBookingAmount: (json['min_booking_amount'] as num?)?.toDouble() ?? 0,
      freeNightsConfig: json['free_nights_config'] != null
          ? FreeNightsConfig.fromJson(
              json['free_nights_config'] as Map<String, dynamic>)
          : null,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: json['ends_at'] != null
          ? DateTime.parse(json['ends_at'] as String)
          : null,
      totalUsageLimit: json['total_usage_limit'] as int?,
      perUserLimit: json['per_user_limit'] as int? ?? 1,
      currentUsageCount: json['current_usage_count'] as int? ?? 0,
      eligibleUserIds: (json['eligible_user_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      eligibleListingIds: (json['eligible_listing_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      eligibleHostIds: (json['eligible_host_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      minNights: json['min_nights'] as int? ?? 1,
      maxNights: json['max_nights'] as int?,
      newUsersOnly: json['new_users_only'] as bool? ?? false,
      firstBookingOnly: json['first_booking_only'] as bool? ?? false,
      bookingStartDate: json['booking_start_date'] != null
          ? DateTime.parse(json['booking_start_date'] as String)
          : null,
      bookingEndDate: json['booking_end_date'] != null
          ? DateTime.parse(json['booking_end_date'] as String)
          : null,
      checkInStartDate: json['check_in_start_date'] != null
          ? DateTime.parse(json['check_in_start_date'] as String)
          : null,
      checkInEndDate: json['check_in_end_date'] != null
          ? DateTime.parse(json['check_in_end_date'] as String)
          : null,
      allowedCheckInDays: (json['allowed_check_in_days'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
      stackingBehavior: StackingBehaviorExtension.fromDatabase(
          json['stacking_behavior'] as String? ?? 'best_only'),
      stackableWithCategories:
          (json['stackable_with_categories'] as List<dynamic>?)
              ?.map((e) => DiscountCategoryExtension.fromDatabase(e as String))
              .toList(),
      priority: json['priority'] as int? ?? 100,
      createdBy: json['created_by'] as String?,
      hostId: json['host_id'] as String?,
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
      'code': code,
      'name': name,
      'description': description,
      'type': type.databaseValue,
      'category': category.databaseValue,
      'status': status.databaseValue,
      'value': value,
      'max_discount_amount': maxDiscountAmount,
      'min_booking_amount': minBookingAmount,
      'free_nights_config': freeNightsConfig?.toJson(),
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt?.toIso8601String(),
      'total_usage_limit': totalUsageLimit,
      'per_user_limit': perUserLimit,
      'current_usage_count': currentUsageCount,
      'eligible_user_ids': eligibleUserIds,
      'eligible_listing_ids': eligibleListingIds,
      'eligible_host_ids': eligibleHostIds,
      'min_nights': minNights,
      'max_nights': maxNights,
      'new_users_only': newUsersOnly,
      'first_booking_only': firstBookingOnly,
      'booking_start_date': bookingStartDate?.toIso8601String(),
      'booking_end_date': bookingEndDate?.toIso8601String(),
      'check_in_start_date': checkInStartDate?.toIso8601String(),
      'check_in_end_date': checkInEndDate?.toIso8601String(),
      'allowed_check_in_days': allowedCheckInDays,
      'stacking_behavior': stackingBehavior.databaseValue,
      'stackable_with_categories':
          stackableWithCategories?.map((e) => e.databaseValue).toList(),
      'priority': priority,
      'created_by': createdBy,
      'host_id': hostId,
      'metadata': metadata,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Discount copyWith({
    String? id,
    String? code,
    String? name,
    String? description,
    DiscountType? type,
    DiscountCategory? category,
    DiscountStatus? status,
    double? value,
    double? maxDiscountAmount,
    double? minBookingAmount,
    FreeNightsConfig? freeNightsConfig,
    DateTime? startsAt,
    DateTime? endsAt,
    int? totalUsageLimit,
    int? perUserLimit,
    int? currentUsageCount,
    List<String>? eligibleUserIds,
    List<String>? eligibleListingIds,
    List<String>? eligibleHostIds,
    int? minNights,
    int? maxNights,
    bool? newUsersOnly,
    bool? firstBookingOnly,
    DateTime? bookingStartDate,
    DateTime? bookingEndDate,
    DateTime? checkInStartDate,
    DateTime? checkInEndDate,
    List<int>? allowedCheckInDays,
    StackingBehavior? stackingBehavior,
    List<DiscountCategory>? stackableWithCategories,
    int? priority,
    String? createdBy,
    String? hostId,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Discount(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      category: category ?? this.category,
      status: status ?? this.status,
      value: value ?? this.value,
      maxDiscountAmount: maxDiscountAmount ?? this.maxDiscountAmount,
      minBookingAmount: minBookingAmount ?? this.minBookingAmount,
      freeNightsConfig: freeNightsConfig ?? this.freeNightsConfig,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      totalUsageLimit: totalUsageLimit ?? this.totalUsageLimit,
      perUserLimit: perUserLimit ?? this.perUserLimit,
      currentUsageCount: currentUsageCount ?? this.currentUsageCount,
      eligibleUserIds: eligibleUserIds ?? this.eligibleUserIds,
      eligibleListingIds: eligibleListingIds ?? this.eligibleListingIds,
      eligibleHostIds: eligibleHostIds ?? this.eligibleHostIds,
      minNights: minNights ?? this.minNights,
      maxNights: maxNights ?? this.maxNights,
      newUsersOnly: newUsersOnly ?? this.newUsersOnly,
      firstBookingOnly: firstBookingOnly ?? this.firstBookingOnly,
      bookingStartDate: bookingStartDate ?? this.bookingStartDate,
      bookingEndDate: bookingEndDate ?? this.bookingEndDate,
      checkInStartDate: checkInStartDate ?? this.checkInStartDate,
      checkInEndDate: checkInEndDate ?? this.checkInEndDate,
      allowedCheckInDays: allowedCheckInDays ?? this.allowedCheckInDays,
      stackingBehavior: stackingBehavior ?? this.stackingBehavior,
      stackableWithCategories:
          stackableWithCategories ?? this.stackableWithCategories,
      priority: priority ?? this.priority,
      createdBy: createdBy ?? this.createdBy,
      hostId: hostId ?? this.hostId,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Discount && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
