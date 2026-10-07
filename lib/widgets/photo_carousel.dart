import 'package:flutter/material.dart';

import 'app_network_image.dart';

/// A swipeable photo strip with dots, step arrows and an "N photos" chip.
///
/// The arrows are not decoration: a [PageView] only responds to touch drags
/// by default, so on a desktop browser (web is the primary target) a mouse
/// cannot swipe it and every photo after the first is unreachable. Tapping a
/// photo calls [onOpen] with the current index, for a full-screen gallery.
class PhotoCarousel extends StatefulWidget {
  const PhotoCarousel({
    super.key,
    required this.urls,
    this.onOpen,
    this.borderRadius,
    this.decodeWidth = 1200,
  });

  final List<String> urls;
  final ValueChanged<int>? onOpen;
  final BorderRadius? borderRadius;
  final int decodeWidth;

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void didUpdateWidget(covariant PhotoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A reload can hand over fewer photos than the page we are on; snap back
    // rather than leave the dots pointing past the end.
    if (_page >= widget.urls.length && widget.urls.isNotEmpty) {
      _page = 0;
      if (_controller.hasClients) _controller.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final target = (_page + delta).clamp(0, widget.urls.length - 1);
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    final count = urls.length;
    final theme = Theme.of(context);

    final strip = PageView.builder(
      controller: _controller,
      itemCount: count,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (context, i) => GestureDetector(
        onTap: widget.onOpen == null ? null : () => widget.onOpen!(i),
        child: AppNetworkImage(
          url: urls[i],
          fit: BoxFit.cover,
          decodeWidth: widget.decodeWidth,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          strip,
          if (count > 1) ...[
            if (_page > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: _ArrowButton(
                  icon: Icons.chevron_left_rounded,
                  label: 'Previous photo',
                  onPressed: () => _step(-1),
                ),
              ),
            if (_page < count - 1)
              Align(
                alignment: Alignment.centerRight,
                child: _ArrowButton(
                  icon: Icons.chevron_right_rounded,
                  label: 'Next photo',
                  onPressed: () => _step(1),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: IgnorePointer(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < count; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        width: i == _page ? 18 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white
                              .withValues(alpha: i == _page ? 1 : 0.55),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_page + 1} / $count',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // A Tooltip does not name a control for a screen reader; Semantics does.
    return Semantics(
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: Colors.white.withValues(alpha: 0.92),
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 22, color: Colors.grey[900]),
            ),
          ),
        ),
      ),
    );
  }
}
