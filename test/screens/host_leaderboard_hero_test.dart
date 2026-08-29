import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/leaderboard_entry.dart';
import 'package:musafir/repositories/musafir_repository.dart';
import 'package:musafir/screens/leaderboard/host_leaderboard_screen.dart';

class _FakeRepo extends Fake implements MusafirRepository {
  @override
  Future<List<LeaderboardEntry>> getHostLeaderboard({
    required LeaderboardPeriod period,
    int limit = 100,
    int offset = 0,
  }) async =>
      const [
        LeaderboardEntry(
          rank: 1,
          hostId: 'h1',
          name: 'Host One',
          score: 95,
          rating: 4.9,
          reviewCount: 100,
          completedBookings: 50,
        ),
      ];
}

/// Reproduces the trap the hero has to survive: this app's `appBarTheme`
/// pins the title to a near-black ink, and Flutter resolves
/// `appBarTheme.titleTextStyle` *before* anything tinted by the app bar's own
/// `foregroundColor` (material/app_bar.dart). A hero drawn on the dark brand
/// gradient therefore has to state its colour itself.
ThemeData _themeWithInkAppBarTitle() => ThemeData(
      fontFamily: 'Arial',
      appBarTheme: const AppBarTheme(
        titleTextStyle: TextStyle(fontSize: 22, color: Color(0xFF0E1F23)),
      ),
    );

Future<void> _pump(WidgetTester tester, {double textScale = 1.0}) async {
  await tester.pumpWidget(MaterialApp(
    theme: _themeWithInkAppBarTitle(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: HostLeaderboardScreen(repository: _FakeRepo()),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the hero title is white whatever the app bar theme says',
      (tester) async {
    await _pump(tester);

    // The rendered style, not the widget's own: this is the merge of the
    // ambient DefaultTextStyle with what the header asked for, which is the
    // thing that actually reaches the screen.
    final rendered =
        tester.renderObject<RenderParagraph>(find.text('Top Hosts'));
    expect(rendered.text.style?.color, Colors.white,
        reason: 'a near-black title on the brand gradient is ~2:1');
  });

  testWidgets('the header grows with the text scale so nothing is clipped',
      (tester) async {
    await _pump(tester);
    final atOne =
        tester.widget<SliverAppBar>(find.byType(SliverAppBar)).expandedHeight!;

    await _pump(tester, textScale: 1.6);
    final atLarge =
        tester.widget<SliverAppBar>(find.byType(SliverAppBar)).expandedHeight!;

    // A fixed height is what used to clip the tagline — and, when the title
    // still lived in FlexibleSpaceBar, drop the title on top of it.
    expect(atLarge, greaterThan(atOne));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the tagline is readable rather than overflowing',
      (tester) async {
    await _pump(tester, textScale: 1.6);

    expect(find.textContaining('most loved hosts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
