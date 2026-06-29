/// Time window for the host leaderboard.
enum LeaderboardPeriod { monthly, allTime }

extension LeaderboardPeriodX on LeaderboardPeriod {
  /// Value sent to the `get_host_leaderboard` RPC.
  String get apiValue =>
      this == LeaderboardPeriod.monthly ? 'monthly' : 'all_time';

  String get label =>
      this == LeaderboardPeriod.monthly ? 'This month' : 'All-time';
}

/// One ranked host row from the leaderboard RPC. Read-only: the score and rank
/// are computed in the database (single source of truth).
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.hostId,
    required this.name,
    this.avatarUrl,
    required this.score,
    required this.rating,
    required this.reviewCount,
    required this.completedBookings,
    this.prevRank,
  });

  final int rank;
  final String hostId;
  final String name;
  final String? avatarUrl;
  final double score;
  final double rating;
  final int reviewCount;
  final int completedBookings;

  /// This host's rank in the previous month (from the snapshot). Null for the
  /// all-time board, or when the host wasn't ranked last month.
  final int? prevRank;

  /// Positions gained since last month (positive = moved up, negative = down,
  /// 0 = unchanged). Null when there's no prior-month baseline.
  int? get rankChange => prevRank == null ? null : prevRank! - rank;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      hostId: json['host_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Host',
      avatarUrl: json['avatar_url'] as String?,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      completedBookings: (json['completed_bookings'] as num?)?.toInt() ?? 0,
      prevRank: (json['prev_rank'] as num?)?.toInt(),
    );
  }
}
