import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/campaign.dart';

/// Style variants for campaign banner
enum CampaignBannerStyle {
  /// Full width banner with image
  full,

  /// Compact card style
  card,

  /// Hero banner for home screen
  hero,

  /// Minimal inline banner
  minimal,
}

/// Campaign banner widget
class CampaignBanner extends StatelessWidget {
  const CampaignBanner({
    super.key,
    required this.campaign,
    this.style = CampaignBannerStyle.card,
    this.onTap,
    this.discountLabel,
    this.height,
  });

  final Campaign campaign;
  final CampaignBannerStyle style;
  final VoidCallback? onTap;
  final String? discountLabel;
  final double? height;

  @override
  Widget build(BuildContext context) {
    switch (style) {
      case CampaignBannerStyle.full:
        return _buildFullBanner(context);
      case CampaignBannerStyle.card:
        return _buildCardBanner(context);
      case CampaignBannerStyle.hero:
        return _buildHeroBanner(context);
      case CampaignBannerStyle.minimal:
        return _buildMinimalBanner(context);
    }
  }

  Widget _buildFullBanner(BuildContext context) {
    final theme = Theme.of(context);
    final bannerColor = campaign.color ?? theme.colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height ?? 180,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              bannerColor.withValues(alpha: 0.8),
              bannerColor,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          image: campaign.bannerImageUrl != null
              ? DecorationImage(
                  image: NetworkImage(campaign.bannerImageUrl!),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    bannerColor.withValues(alpha: 0.3),
                    BlendMode.srcOver,
                  ),
                )
              : null,
        ),
        child: Stack(
          children: [
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.5),
                  ],
                ),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (discountLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        discountLabel!,
                        style: TextStyle(
                          color: bannerColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    campaign.bannerTitle ?? campaign.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (campaign.bannerSubtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      campaign.bannerSubtitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                  if (campaign.showCountdown && campaign.isActive) ...[
                    const SizedBox(height: 12),
                    CampaignCountdown(campaign: campaign),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBanner(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bannerColor = campaign.color ?? colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height ?? 140,
          child: Row(
            children: [
              // Image or color block
              Container(
                width: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      bannerColor.withValues(alpha: 0.8),
                      bannerColor,
                    ],
                  ),
                  image: campaign.bannerImageUrl != null
                      ? DecorationImage(
                          image: NetworkImage(campaign.bannerImageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: campaign.bannerImageUrl == null
                    ? Center(
                        child: Icon(
                          Icons.local_offer,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: 40,
                        ),
                      )
                    : null,
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (discountLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: bannerColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            discountLabel!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      Text(
                        campaign.bannerTitle ?? campaign.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (campaign.bannerSubtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          campaign.bannerSubtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (campaign.showCountdown && campaign.isActive) ...[
                        const SizedBox(height: 8),
                        CampaignCountdown(
                          campaign: campaign,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Arrow
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner(BuildContext context) {
    final theme = Theme.of(context);
    final bannerColor = campaign.color ?? theme.colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height ?? 220,
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: bannerColor.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background
              if (campaign.bannerImageUrl != null)
                Image.network(
                  campaign.bannerImageUrl!,
                  fit: BoxFit.cover,
                )
              else
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        bannerColor.withValues(alpha: 0.8),
                        bannerColor,
                      ],
                    ),
                  ),
                ),

              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Discount badge
                    if (discountLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          discountLabel!,
                          style: TextStyle(
                            color: bannerColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),

                    const Spacer(),

                    // Title
                    Text(
                      campaign.bannerTitle ?? campaign.name,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    if (campaign.bannerSubtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        campaign.bannerSubtitle!,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],

                    // Countdown
                    if (campaign.showCountdown && campaign.isActive) ...[
                      const SizedBox(height: 16),
                      CampaignCountdown(campaign: campaign),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalBanner(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bannerColor = campaign.color ?? colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bannerColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.local_offer, color: bannerColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    campaign.bannerTitle ?? campaign.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: bannerColor,
                    ),
                  ),
                  if (discountLabel != null)
                    Text(
                      discountLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: bannerColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Countdown timer for campaigns
class CampaignCountdown extends StatefulWidget {
  const CampaignCountdown({
    super.key,
    required this.campaign,
    this.compact = false,
    this.textColor = Colors.white,
  });

  final Campaign campaign;
  final bool compact;
  final Color textColor;

  @override
  State<CampaignCountdown> createState() => _CampaignCountdownState();
}

class _CampaignCountdownState extends State<CampaignCountdown> {
  Timer? _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.campaign.timeRemaining;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remaining = widget.campaign.timeRemaining;
        if (_remaining <= Duration.zero) {
          timer.cancel();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining <= Duration.zero) {
      return Text(
        'Ended',
        style: TextStyle(
          color: widget.textColor,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final days = _remaining.inDays;
    final hours = _remaining.inHours % 24;
    final minutes = _remaining.inMinutes % 60;
    final seconds = _remaining.inSeconds % 60;

    if (widget.compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 14,
            color: widget.textColor.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 4),
          Text(
            days > 0
                ? '${days}d ${hours}h left'
                : hours > 0
                    ? '${hours}h ${minutes}m left'
                    : '${minutes}m ${seconds}s left',
            style: TextStyle(
              color: widget.textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.timer_outlined,
          color: widget.textColor.withValues(alpha: 0.8),
          size: 18,
        ),
        const SizedBox(width: 8),
        Text(
          'Ends in: ',
          style: TextStyle(
            color: widget.textColor.withValues(alpha: 0.8),
            fontSize: 14,
          ),
        ),
        if (days > 0)
          _buildTimeUnit(days.toString().padLeft(2, '0'), 'D'),
        _buildTimeUnit(hours.toString().padLeft(2, '0'), 'H'),
        _buildTimeUnit(minutes.toString().padLeft(2, '0'), 'M'),
        _buildTimeUnit(seconds.toString().padLeft(2, '0'), 'S'),
      ],
    );
  }

  Widget _buildTimeUnit(String value, String label) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: widget.textColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              color: widget.textColor.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Campaign list carousel
class CampaignCarousel extends StatelessWidget {
  const CampaignCarousel({
    super.key,
    required this.campaigns,
    this.onCampaignTap,
    this.style = CampaignBannerStyle.card,
    this.height,
  });

  final List<Campaign> campaigns;
  final void Function(Campaign)? onCampaignTap;
  final CampaignBannerStyle style;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (campaigns.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: height ?? (style == CampaignBannerStyle.hero ? 220 : 160),
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.9),
        itemCount: campaigns.length,
        itemBuilder: (context, index) {
          final campaign = campaigns[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CampaignBanner(
              campaign: campaign,
              style: style,
              onTap: () => onCampaignTap?.call(campaign),
            ),
          );
        },
      ),
    );
  }
}
