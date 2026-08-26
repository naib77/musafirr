import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/core/theme/app_colors.dart';
import 'package:musafir/core/theme/app_palettes.dart';
import 'package:musafir/widgets/brand_logo.dart';

/// The mark appears on the splash screen, the login screen and the desktop
/// sidebar — three places a user sees before anything else. The behaviour worth
/// pinning is therefore not what it looks like but that it always renders
/// *something*.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester
      .pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));

  tearDown(() => AppColors.usePalette(AppPalettes.fallback));

  testWidgets('falls back to a glyph when the asset is missing',
      (tester) async {
    // The load-bearing case: branding half-applied — pubspec declares the asset
    // but the PNG is absent, or it is corrupt. A broken-image box on the splash
    // screen would be the first thing a new user ever saw.
    await pump(tester, const BrandLogo(assetPath: 'assets/brand/nope.png'));
    await tester.pump();

    expect(find.byIcon(Icons.travel_explore_rounded), findsOneWidget);
  });

  testWidgets('the fallback keeps the requested size and colour',
      (tester) async {
    await pump(
      tester,
      const BrandLogo(
        assetPath: 'assets/brand/nope.png',
        size: 42,
        color: Color(0xFF123456),
      ),
    );
    await tester.pump();

    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, 42);
    expect(icon.color, const Color(0xFF123456));
  });

  testWidgets('an untinted fallback takes the active palette brand',
      (tester) async {
    // Not a hardcoded teal: the fallback has to follow the admin's theme too,
    // or a missing asset also silently reverts the app's colour.
    AppColors.usePalette(AppPalettes.crimsonEmber);

    await pump(tester, const BrandLogo(assetPath: 'assets/brand/nope.png'));
    await tester.pump();

    expect(tester.widget<Icon>(find.byType(Icon)).color,
        AppPalettes.crimsonEmber.brand);
  });

  testWidgets('renders the real asset when it is present', (tester) async {
    await pump(tester, const BrandLogo(size: 64));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.width, 64);
    // srcIn is what makes one white silhouette work across four palettes;
    // without it a tint would wash the whole box instead of the mark.
    expect(image.colorBlendMode, isNull, reason: 'no tint requested');
  });

  testWidgets('stays square inside a stretching Column', (tester) async {
    // The login screen's Column uses CrossAxisAlignment.stretch, which hands
    // children a TIGHT width. An Image with width/height set cannot refuse that,
    // so an unwrapped BrandLogo would be painted full-width and 80 tall — the
    // mark stretched sideways. The call site wraps it in a Center; this asserts
    // that wrapping actually works, on the real asset.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const [Center(child: BrandLogo(size: 80))],
          ),
        ),
      ),
    );
    await tester.pump();

    final box = tester.getSize(find.byType(Image));
    expect(box.width, 80);
    expect(box.height, 80);
  });

  testWidgets('a tinted asset repaints through srcIn', (tester) async {
    await pump(tester, const BrandLogo(size: 64, color: Color(0xFF00FF00)));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.color, const Color(0xFF00FF00));
    expect(image.colorBlendMode, BlendMode.srcIn);
  });
}
