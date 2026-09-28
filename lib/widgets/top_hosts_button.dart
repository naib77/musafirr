import 'package:flutter/material.dart';

/// The gold trophy that opens the Top Hosts leaderboard.
///
/// Gold rather than another grey action chip because the leaderboard is a
/// reward surface — it should read as worth tapping, not as a fourth utility
/// icon. The gradient is fixed, not palette-derived, for the same reason a
/// medal is gold in every brand.
///
/// Shared because it appears twice: inside the Explore tab's search row on
/// mobile, and in the desktop header's action group. It was duplicated at
/// first, and a hand-tuned gradient with a matching shadow is exactly the kind
/// of thing that gets adjusted in one copy only.
class TopHostsButton extends StatelessWidget {
  const TopHostsButton({super.key, required this.onTap, this.padding = 9});

  final VoidCallback onTap;

  /// Inner padding around the 22px glyph. The default gives a 40px target;
  /// the header nudges it up to match the notification bell beside it.
  final double padding;

  static const Color _gold = Color(0xFFFFB300);
  static const Color _goldDeep = Color(0xFFFF8F00);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Top hosts',
      child: Tooltip(
        message: 'Top Hosts',
        child: Material(
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: EdgeInsets.all(padding),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_gold, _goldDeep],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _gold.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
