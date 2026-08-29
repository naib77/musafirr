import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/models/booking.dart';
import 'package:musafir/models/leaderboard_entry.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/listing_type.dart';
import 'package:musafir/models/user.dart';
import 'package:musafir/models/user_role.dart';
import 'package:musafir/repositories/musafir_repository.dart';
import 'package:musafir/screens/host/host_dashboard_screen.dart';
import 'package:musafir/state/auth_state.dart';

/// Both fakes extend ChangeNotifier so the screen's `Listenable.merge` gets a
/// real Listenable, and lean on noSuchMethod for the rest of the (very large)
/// interfaces. Returning null rather than throwing matters: the dashboard
/// touches a lot of the repository, and this test is about one card.
class _FakeRepo extends ChangeNotifier implements MusafirRepository {
  _FakeRepo(this._listings);
  final List<Listing> _listings;

  @override
  List<Listing> get listings => _listings;
  @override
  List<Booking> get bookings => const [];

  // Explicit because the dashboard's rank card awaits this: a noSuchMethod null
  // is not a Future and blows up mid-build before Quick Actions ever renders.
  @override
  Future<LeaderboardEntry?> getMyHostRank({
    required String hostId,
    required LeaderboardPeriod period,
  }) async =>
      null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuth extends ChangeNotifier implements AuthStateNotifier {
  _FakeAuth(this._user);
  final User? _user;

  @override
  User? get currentUser => _user;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Listing _listing(String id, String hostId) => Listing(
      id: id,
      ownerName: 'Host',
      title: 'Listing $id',
      address: 'Dhanmondi',
      type: ListingType.room,
      latitude: 23.75,
      longitude: 90.38,
      facilities: const [],
      available: true,
      hostId: hostId,
      dailyRate: 1000,
    );

const _host = User(id: 'h1', name: 'Naib', role: UserRole.owner, isHost: true);

Future<void> _pump(WidgetTester tester, List<Listing> listings,
    {User? user = _host}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: HostDashboardScreen(
        repository: _FakeRepo(listings),
        authState: _FakeAuth(user),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  // The card is gated on `hostListings.isNotEmpty`, and it is the ONLY entry
  // point to blocking dates from the dashboard. If that gate is ever widened or
  // the card is dropped in a refactor, a host loses the discoverable route to
  // the feature and the only way in is knowing to open a listing first.
  testWidgets('a host with listings sees the Availability quick action',
      (tester) async {
    await _pump(tester, [_listing('l1', 'h1')]);

    final card = find.text('Availability');
    await tester.scrollUntilVisible(card, 200,
        scrollable: find.byType(Scrollable).first);

    expect(card, findsOneWidget);
    expect(
        find.text('Block dates without hiding your listing'), findsOneWidget);
  });

  testWidgets('with several listings the copy points at the listing list',
      (tester) async {
    await _pump(tester, [_listing('l1', 'h1'), _listing('l2', 'h1')]);

    final card = find.text('Availability');
    await tester.scrollUntilVisible(card, 200,
        scrollable: find.byType(Scrollable).first);

    expect(find.text('Block dates on any of your listings'), findsOneWidget);
  });

  testWidgets('a host with no listings is not offered it', (tester) async {
    // Nothing to block yet, so the card would be a dead end. The Away switch at
    // the top of the dashboard is a different control and stays regardless.
    await _pump(tester, const []);
    expect(find.text('Availability'), findsNothing);
  });

  testWidgets("another host's listings do not count", (tester) async {
    // The filter is `l.hostId == user.id`. If that ever broadens, this host
    // would be offered a screen that manages someone else's dates.
    await _pump(tester, [_listing('l1', 'someone-else')]);
    expect(find.text('Availability'), findsNothing);
  });
}
