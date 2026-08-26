import 'package:flutter/material.dart';

import '../../core/theme/brand.dart';
import '../../widgets/brand_logo.dart';

/// Splash screen shown during app initialization.
///
/// Displays the app logo and a loading indicator while
/// authentication state is being determined.
///
/// ## Why this is brand rose and not `colorScheme.primary`
///
/// This is the last link in a boot chain that starts long before Dart: the
/// launcher icon, the OS launch window (Android `values-v31`, iOS
/// `LaunchScreen.storyboard`) and the web boot splash in `index.html` all paint
/// [Brand.rose], because none of them can know which palette an admin selected.
/// Painting the theme's primary here made that handover visible — a rose
/// launch window flipping to a teal screen on the default palette — which read
/// as a broken load rather than a brand. See [Brand].
///
/// The app proper still wears the active palette; only the pre-auth moment is
/// pinned to the brand.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Brand.rose,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The mark knocked out in white, directly on the rose — no white
            // tile. This is pixel-for-pixel what the OS launch window and the
            // web boot splash already show, so the handover into Dart is
            // invisible instead of being a second, differently-styled splash.
            // 98, not a round number: logo.png carries the mark at 86% of its
            // width while the index.html splash draws Icon-192, which carries
            // it at 60%. 0.86*98 == 0.60*140 == 84px, so the mark does not
            // change size when the web boot splash hands over to this screen.
            const BrandLogo(size: 98, color: Colors.white),
            const SizedBox(height: 24),
            // App name
            Text(
              'Musaafir',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Find your perfect stay',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 48),
            // Loading indicator
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
