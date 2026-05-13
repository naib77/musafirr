import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Campaign status
enum CampaignStatus {
  draft,
  scheduled,
  active,
  ended,
}

extension CampaignStatusExtension on CampaignStatus {
  String get displayName {
    switch (this) {
      case CampaignStatus.draft:
        return 'Draft';
      case CampaignStatus.scheduled:
        return 'Scheduled';
      case CampaignStatus.active:
        return 'Active';
      case CampaignStatus.ended:
        return 'Ended';
    }
  }

  String get databaseValue {
    switch (this) {
      case CampaignStatus.draft:
        return 'draft';
      case CampaignStatus.scheduled:
        return 'scheduled';
      case CampaignStatus.active:
        return 'active';
      case CampaignStatus.ended:
        return 'ended';
    }
  }

  static CampaignStatus fromDatabase(String value) {
    switch (value) {
      case 'draft':
        return CampaignStatus.draft;
      case 'scheduled':
        return CampaignStatus.scheduled;
      case 'active':
        return CampaignStatus.active;
      case 'ended':
        return CampaignStatus.ended;
      default:
        return CampaignStatus.draft;
    }
  }

  Color get color {
    switch (this) {
      case CampaignStatus.draft:
        return Colors.grey;
      case CampaignStatus.scheduled:
        return Colors.blue;
      case CampaignStatus.active:
        return Colors.green;
      case CampaignStatus.ended:
        return Colors.red;
    }
  }
}

/// Target user segments for campaigns
@immutable
class CampaignTargeting {
  const CampaignTargeting({
    this.newUsersOnly = false,
    this.loyaltyTiers,
    this.minBookings,
    this.maxBookings,
    this.userIds,
    this.excludeUserIds,
  });

  final bool newUsersOnly;
  final List<String>? loyaltyTiers;
  final int? minBookings;
  final int? maxBookings;
  final List<String>? userIds;
  final List<String>? excludeUserIds;

  factory CampaignTargeting.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CampaignTargeting();

    return CampaignTargeting(
      newUsersOnly: json['new_users_only'] as bool? ?? false,
      loyaltyTiers: json['loyalty_tiers'] != null
          ? List<String>.from(json['loyalty_tiers'] as List)
          : null,
      minBookings: json['min_bookings'] as int?,
      maxBookings: json['max_bookings'] as int?,
      userIds: json['user_ids'] != null
          ? List<String>.from(json['user_ids'] as List)
          : null,
      excludeUserIds: json['exclude_user_ids'] != null
          ? List<String>.from(json['exclude_user_ids'] as List)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'new_users_only': newUsersOnly,
      if (loyaltyTiers != null) 'loyalty_tiers': loyaltyTiers,
      if (minBookings != null) 'min_bookings': minBookings,
      if (maxBookings != null) 'max_bookings': maxBookings,
      if (userIds != null) 'user_ids': userIds,
      if (excludeUserIds != null) 'exclude_user_ids': excludeUserIds,
    };
  }

  /// Check if targeting allows all users
  bool get isTargetingAll {
    return !newUsersOnly &&
        loyaltyTiers == null &&
        minBookings == null &&
        maxBookings == null &&
        userIds == null;
  }

  /// Check if user matches targeting criteria
  bool matchesUser({
    required bool isNewUser,
    String? loyaltyTier,
    int? totalBookings,
    String? userId,
  }) {
    // Check new users only
    if (newUsersOnly && !isNewUser) return false;

    // Check loyalty tiers
    if (loyaltyTiers != null &&
        loyaltyTier != null &&
        !loyaltyTiers!.contains(loyaltyTier)) {
      return false;
    }

    // Check booking count
    if (minBookings != null &&
        totalBookings != null &&
        totalBookings < minBookings!) {
      return false;
    }
    if (maxBookings != null &&
        totalBookings != null &&
        totalBookings > maxBookings!) {
      return false;
    }

    // Check specific users
    if (userIds != null && userId != null && !userIds!.contains(userId)) {
      return false;
    }

    // Check excluded users
    if (excludeUserIds != null &&
        userId != null &&
        excludeUserIds!.contains(userId)) {
      return false;
    }

    return true;
  }
}

/// Marketing campaign model
@immutable
class Campaign {
  const Campaign({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.bannerImageUrl,
    this.bannerTitle,
    this.bannerSubtitle,
    this.highlightColor,
    required this.startsAt,
    required this.endsAt,
    this.discountIds,
    this.targeting,
    this.featuredListingIds,
    this.status = CampaignStatus.draft,
    this.showOnHome = true,
    this.showOnExplore = true,
    this.showCountdown = false,
    this.metadata,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String slug;
  final String? description;
  final String? bannerImageUrl;
  final String? bannerTitle;
  final String? bannerSubtitle;
  final String? highlightColor;
  final DateTime startsAt;
  final DateTime endsAt;
  final List<String>? discountIds;
  final CampaignTargeting? targeting;
  final List<String>? featuredListingIds;
  final CampaignStatus status;
  final bool showOnHome;
  final bool showOnExplore;
  final bool showCountdown;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Check if campaign is currently active
  bool get isActive {
    final now = DateTime.now();
    return status == CampaignStatus.active &&
        now.isAfter(startsAt) &&
        now.isBefore(endsAt);
  }

  /// Check if campaign has ended
  bool get hasEnded {
    return DateTime.now().isAfter(endsAt);
  }

  /// Check if campaign is upcoming
  bool get isUpcoming {
    return DateTime.now().isBefore(startsAt);
  }

  /// Get time remaining until campaign ends
  Duration get timeRemaining {
    final now = DateTime.now();
    if (now.isAfter(endsAt)) return Duration.zero;
    return endsAt.difference(now);
  }

  /// Get time until campaign starts
  Duration get timeUntilStart {
    final now = DateTime.now();
    if (now.isAfter(startsAt)) return Duration.zero;
    return startsAt.difference(now);
  }

  /// Get campaign duration
  Duration get duration => endsAt.difference(startsAt);

  /// Get progress percentage (0-100)
  double get progress {
    final now = DateTime.now();
    if (now.isBefore(startsAt)) return 0;
    if (now.isAfter(endsAt)) return 100;

    final total = duration.inMilliseconds;
    final elapsed = now.difference(startsAt).inMilliseconds;
    return (elapsed / total) * 100;
  }

  /// Get the highlight color as a Color object
  Color? get color {
    if (highlightColor == null) return null;
    try {
      return Color(int.parse(highlightColor!.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  /// Check if campaign has featured listings
  bool get hasFeaturedListings =>
      featuredListingIds != null && featuredListingIds!.isNotEmpty;

  /// Check if campaign has discounts
  bool get hasDiscounts => discountIds != null && discountIds!.isNotEmpty;

  factory Campaign.fromJson(Map<String, dynamic> json) {
    return Campaign(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      bannerImageUrl: json['banner_image_url'] as String?,
      bannerTitle: json['banner_title'] as String?,
      bannerSubtitle: json['banner_subtitle'] as String?,
      highlightColor: json['highlight_color'] as String?,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      discountIds: json['discount_ids'] != null
          ? List<String>.from(json['discount_ids'] as List)
          : null,
      targeting: json['target_user_segments'] != null
          ? CampaignTargeting.fromJson(
              json['target_user_segments'] as Map<String, dynamic>)
          : null,
      featuredListingIds: json['featured_listing_ids'] != null
          ? List<String>.from(json['featured_listing_ids'] as List)
          : null,
      status:
          CampaignStatusExtension.fromDatabase(json['status'] as String? ?? 'draft'),
      showOnHome: json['show_on_home'] as bool? ?? true,
      showOnExplore: json['show_on_explore'] as bool? ?? true,
      showCountdown: json['show_countdown'] as bool? ?? false,
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
      'slug': slug,
      'description': description,
      'banner_image_url': bannerImageUrl,
      'banner_title': bannerTitle,
      'banner_subtitle': bannerSubtitle,
      'highlight_color': highlightColor,
      'starts_at': startsAt.toIso8601String(),
      'ends_at': endsAt.toIso8601String(),
      'discount_ids': discountIds,
      'target_user_segments': targeting?.toJson(),
      'featured_listing_ids': featuredListingIds,
      'status': status.databaseValue,
      'show_on_home': showOnHome,
      'show_on_explore': showOnExplore,
      'show_countdown': showCountdown,
      'metadata': metadata,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Campaign copyWith({
    String? id,
    String? name,
    String? slug,
    String? description,
    String? bannerImageUrl,
    String? bannerTitle,
    String? bannerSubtitle,
    String? highlightColor,
    DateTime? startsAt,
    DateTime? endsAt,
    List<String>? discountIds,
    CampaignTargeting? targeting,
    List<String>? featuredListingIds,
    CampaignStatus? status,
    bool? showOnHome,
    bool? showOnExplore,
    bool? showCountdown,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Campaign(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      bannerImageUrl: bannerImageUrl ?? this.bannerImageUrl,
      bannerTitle: bannerTitle ?? this.bannerTitle,
      bannerSubtitle: bannerSubtitle ?? this.bannerSubtitle,
      highlightColor: highlightColor ?? this.highlightColor,
      startsAt: startsAt ?? this.startsAt,
      endsAt: endsAt ?? this.endsAt,
      discountIds: discountIds ?? this.discountIds,
      targeting: targeting ?? this.targeting,
      featuredListingIds: featuredListingIds ?? this.featuredListingIds,
      status: status ?? this.status,
      showOnHome: showOnHome ?? this.showOnHome,
      showOnExplore: showOnExplore ?? this.showOnExplore,
      showCountdown: showCountdown ?? this.showCountdown,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Campaign && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Campaign display data for UI
class CampaignDisplay {
  const CampaignDisplay({
    required this.campaign,
    this.discountValue,
    this.discountLabel,
  });

  final Campaign campaign;
  final double? discountValue;
  final String? discountLabel;

  /// Get the main display text
  String get title => campaign.bannerTitle ?? campaign.name;

  /// Get the subtitle
  String? get subtitle => campaign.bannerSubtitle ?? campaign.description;

  /// Get discount display
  String? get discountDisplay {
    if (discountLabel != null) return discountLabel;
    if (discountValue != null) return '${discountValue!.toStringAsFixed(0)}% OFF';
    return null;
  }
}
