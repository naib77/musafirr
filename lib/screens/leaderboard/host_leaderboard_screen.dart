import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../models/leaderboard_entry.dart';
import '../../repositories/musafir_repository.dart';

/// Public "Top Hosts" leaderboard, ranked by the composite Host Score.
///
/// Designed to be *aspirational*: a gradient hero, an animated medal podium for
/// the top three, the viewer's own standing pinned up top, and a clear "how to
/// climb" explainer — the patterns gaming/fitness apps use to make a board feel
/// worth chasing.
class HostLeaderboardScreen extends StatefulWidget {
  const HostLeaderboardScreen({
    super.key,
    required this.repository,
    this.currentUserId,
  });

  final MusafirRepository repository;

  /// Highlights this host's row + pins their standing banner if they're ranked.
  final String? currentUserId;

  @override
  State<HostLeaderboardScreen> createState() => _HostLeaderboardScreenState();
}

class _HostLeaderboardScreenState extends State<HostLeaderboardScreen> {
  LeaderboardPeriod _period = LeaderboardPeriod.allTime;
  late Future<List<LeaderboardEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<LeaderboardEntry>> _load() =>
      widget.repository.getHostLeaderboard(period: _period, limit: 100);

  void _selectPeriod(LeaderboardPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _future = _load();
    });
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _showScoringInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => const _ScoringInfoSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: ResponsiveCenter(
        maxWidth: 760,
        child: FutureBuilder<List<LeaderboardEntry>>(
          future: _future,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final entries = snapshot.data ?? const <LeaderboardEntry>[];

            return RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _HeroHeader(onInfo: _showScoringInfo),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: _PeriodSwitcher(
                          period: _period, onChanged: _selectPeriod),
                    ),
                  ),
                  if (loading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (entries.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(period: _period),
                    )
                  else
                    ..._buildBoard(entries),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildBoard(List<LeaderboardEntry> entries) {
    final me = widget.currentUserId == null
        ? null
        : entries
            .where((e) => e.hostId == widget.currentUserId)
            .cast<LeaderboardEntry?>()
            .firstOrNull;

    final podium = entries.take(3).toList();
    final rest = entries.length > 3 ? entries.sublist(3) : <LeaderboardEntry>[];

    return [
      if (widget.currentUserId != null)
        SliverToBoxAdapter(
          child: _YourStandingBanner(me: me, total: entries.length),
        ),
      SliverToBoxAdapter(child: _Podium(top: podium)),
      if (rest.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LeaderRow(
                  entry: rest[i],
                  highlight: rest[i].hostId == widget.currentUserId,
                ),
              ),
              childCount: rest.length,
            ),
          ),
        ),
      SliverToBoxAdapter(child: _ScoringFooter(onTap: _showScoringInfo)),
    ];
  }
}

/// Gradient hero with a glowing trophy — the first thing the eye lands on.
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.onInfo});

  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverAppBar(
      pinned: true,
      expandedHeight: 168,
      backgroundColor: AppColors.brand,
      foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: const Icon(Icons.help_outline_rounded),
          tooltip: 'How ranking works',
          onPressed: onInfo,
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        title: const Text('Top Hosts',
            style: TextStyle(fontWeight: FontWeight.w800)),
        titlePadding: const EdgeInsets.only(left: 56, bottom: 16),
        background: Container(
          decoration: const BoxDecoration(gradient: AppColors.brandGradient),
          child: Stack(
            children: [
              // Soft decorative glow circles
              Positioned(
                right: -30,
                top: -20,
                child: _glow(120, Colors.white.withValues(alpha: 0.10)),
              ),
              Positioned(
                left: -20,
                bottom: -30,
                child: _glow(140, Colors.white.withValues(alpha: 0.07)),
              ),
              Align(
                alignment: const Alignment(0, -0.15),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(Icons.emoji_events_rounded,
                          color: Color(0xFFFFD54F), size: 30),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'The most loved hosts on Musafir',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// The viewer's own standing, pinned above the board for instant relevance.
/// Ranked → celebratory; unranked → a clear "how to join" nudge.
class _YourStandingBanner extends StatelessWidget {
  const _YourStandingBanner({required this.me, required this.total});

  final LeaderboardEntry? me;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (me == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            const Icon(Icons.rocket_launch_rounded,
                color: AppColors.brand, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                "You're not ranked yet — complete bookings and earn great "
                'reviews to climb onto the board.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.inkMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final entry = me!;
    final topPct =
        total <= 0 ? 0 : ((entry.rank / total) * 100).clamp(1, 100).round();
    final blurb = entry.rank <= 3
        ? "You're on the podium — incredible!"
        : topPct <= 10
            ? "You're in the top $topPct% of hosts!"
            : 'Keep going — every 5-star stay lifts your rank.';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            children: [
              Text(
                '#${entry.rank}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (entry.rankChange != null)
                _RankDelta(change: entry.rankChange!, onDark: true),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Your standing',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  blurb,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ScorePill(score: entry.score, onBrand: true),
        ],
      ),
    );
  }
}

/// Gold/silver/bronze podium with animated pedestals (heights grow on load).
class _Podium extends StatelessWidget {
  const _Podium({required this.top});

  final List<LeaderboardEntry> top;

  static const Color _silver = Color(0xFFB0BEC5);
  static const Color _bronze = Color(0xFFCD7F32);

  @override
  Widget build(BuildContext context) {
    if (top.isEmpty) return const SizedBox.shrink();
    final first = top[0];
    final second = top.length > 1 ? top[1] : null;
    final third = top.length > 2 ? top[2] : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.amber.withValues(alpha: 0.10),
            AppColors.brand.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: second == null
                ? const SizedBox.shrink()
                : _PodiumSpot(
                    entry: second,
                    medalColor: _silver,
                    avatarSize: 58,
                    pedestalHeight: 64,
                  ),
          ),
          Expanded(
            child: _PodiumSpot(
              entry: first,
              medalColor: AppColors.amber,
              avatarSize: 80,
              pedestalHeight: 92,
              crown: true,
            ),
          ),
          Expanded(
            child: third == null
                ? const SizedBox.shrink()
                : _PodiumSpot(
                    entry: third,
                    medalColor: _bronze,
                    avatarSize: 54,
                    pedestalHeight: 48,
                  ),
          ),
        ],
      ),
    );
  }
}

class _PodiumSpot extends StatelessWidget {
  const _PodiumSpot({
    required this.entry,
    required this.medalColor,
    required this.avatarSize,
    required this.pedestalHeight,
    this.crown = false,
  });

  final LeaderboardEntry entry;
  final Color medalColor;
  final double avatarSize;
  final double pedestalHeight;
  final bool crown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (crown)
          const Icon(Icons.workspace_premium_rounded,
              color: AppColors.amber, size: 28)
        else
          const SizedBox(height: 28),
        const SizedBox(height: 4),
        Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: medalColor, width: 3),
                boxShadow: crown
                    ? [
                        BoxShadow(
                          color: AppColors.amber.withValues(alpha: 0.5),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: _Avatar(entry: entry, radius: avatarSize / 2),
            ),
            Positioned(
              bottom: -8,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: medalColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '${entry.rank}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        _ScorePill(score: entry.score),
        const SizedBox(height: 12),
        // Animated pedestal bar
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => Container(
            height: pedestalHeight * t,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  medalColor.withValues(alpha: 0.9),
                  medalColor.withValues(alpha: 0.55),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Center(
              child: Opacity(
                opacity: t,
                child: Text(
                  '#${entry.rank}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({required this.entry, required this.highlight});

  final LeaderboardEntry entry;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.brand.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? AppColors.brand.withValues(alpha: 0.4)
              : AppColors.outline,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${entry.rank}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.rankChange != null)
                  _RankDelta(change: entry.rankChange!),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Avatar(entry: entry, radius: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (highlight) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.brand,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 14, color: AppColors.amber),
                    const SizedBox(width: 2),
                    Text(
                      entry.rating.toStringAsFixed(1),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.event_available_rounded,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text(
                      '${entry.completedBookings}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ScorePill(score: entry.score),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.entry, required this.radius});

  final LeaderboardEntry entry;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = entry.avatarUrl != null && entry.avatarUrl!.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.surfaceMuted,
      backgroundImage: hasImage ? NetworkImage(entry.avatarUrl!) : null,
      child: hasImage
          ? null
          : Text(
              entry.name.isNotEmpty ? entry.name[0].toUpperCase() : 'H',
              style: theme.textTheme.titleMedium,
            ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({required this.score, this.onBrand = false});

  final double score;

  /// When sitting on a brand-gradient surface, invert to a white pill so it
  /// stays legible.
  final bool onBrand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: onBrand ? null : AppColors.brandGradient,
        color: onBrand ? Colors.white.withValues(alpha: 0.22) : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        score.toStringAsFixed(0),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Rank-change indicator vs last month: ▲ green (up), ▼ red (down), – grey.
class _RankDelta extends StatelessWidget {
  const _RankDelta({required this.change, this.onDark = false});

  final int change;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (change == 0) {
      return Icon(Icons.remove,
          size: 12,
          color: onDark
              ? Colors.white.withValues(alpha: 0.8)
              : Theme.of(context).colorScheme.onSurfaceVariant);
    }
    final up = change > 0;
    final color = onDark
        ? Colors.white
        : (up ? AppColors.success : AppColors.error);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 16, color: color),
        Text(
          '${change.abs()}',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PeriodSwitcher extends StatelessWidget {
  const _PeriodSwitcher({required this.period, required this.onChanged});

  final LeaderboardPeriod period;
  final ValueChanged<LeaderboardPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final p in LeaderboardPeriod.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: p == period ? AppColors.brandGradient : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    p.label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: p == period
                          ? Colors.white
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tappable footer that opens the scoring explainer.
class _ScoringFooter extends StatelessWidget {
  const _ScoringFooter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Center(
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.help_outline_rounded, size: 18),
          label: Text(
            'How is the Host Score calculated?',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet explaining the composite score (mirrors the SQL weights in
/// `042_leaderboard_snapshots.sql`: 50% rating, 30% completed stays, 20%
/// response rate).
class _ScoringInfoSheet extends StatelessWidget {
  const _ScoringInfoSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded,
                  color: AppColors.amber, size: 26),
              const SizedBox(width: 10),
              Text(
                'How the Host Score works',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Every host is scored out of 100. New hosts start fair — ratings '
            'are weighted so a single review can’t spike the board.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 20),
          const _ScoreFactor(
            icon: Icons.star_rounded,
            color: AppColors.amber,
            weight: '50%',
            title: 'Guest ratings',
            detail: 'Your average review score from guests.',
          ),
          const _ScoreFactor(
            icon: Icons.event_available_rounded,
            color: AppColors.brand,
            weight: '30%',
            title: 'Completed stays',
            detail: 'How many bookings you’ve successfully hosted.',
          ),
          const _ScoreFactor(
            icon: Icons.bolt_rounded,
            color: AppColors.blue,
            weight: '20%',
            title: 'Response rate',
            detail: 'How reliably you reply to booking requests.',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded,
                    color: AppColors.warning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Rankings refresh continuously, and the monthly board '
                    'resets so newcomers always have a shot at the top.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreFactor extends StatelessWidget {
  const _ScoreFactor({
    required this.icon,
    required this.color,
    required this.weight,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final Color color;
  final String weight;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        weight,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.period});

  final LeaderboardPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_events_outlined,
              size: 64, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            period == LeaderboardPeriod.monthly
                ? 'No ranked hosts this month yet'
                : 'No ranked hosts yet',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Hosts appear here once they complete bookings. Be the first to '
            'climb the board!',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
