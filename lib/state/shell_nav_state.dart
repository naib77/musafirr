import 'package:flutter/foundation.dart';

/// Lets deep screens (e.g. the booking sheet, the notification center) ask the
/// [MainShell] to switch its guest/host tab, without prop-drilling callbacks
/// through the whole tree. The shell listens, applies the request, then calls
/// [consumed] so it fires exactly once.
class ShellNavState extends ChangeNotifier {
  ShellNavState._();
  static final ShellNavState instance = ShellNavState._();

  int? _guestTab;
  int? _hostTab;
  int? _reservationsTab;

  /// Target guest bottom-nav index (2 = Trips), or null if none pending.
  int? get guestTab => _guestTab;

  /// Target host bottom-nav index (1 = Reservations), or null if none pending.
  int? get hostTab => _hostTab;

  /// Target inner tab of the host Reservations screen
  /// (0 = Upcoming, 1 = Active Stays, 2 = Completed), or null.
  int? get reservationsTab => _reservationsTab;

  /// The shell calls this after applying a request so it doesn't re-fire.
  void consumed() {
    _guestTab = null;
    _hostTab = null;
    _reservationsTab = null;
  }

  /// Jump the guest to the Trips tab — used after a booking request is sent.
  void openGuestTrips() {
    _guestTab = 2;
    notifyListeners();
  }

  /// Jump the host to Reservations, optionally selecting an inner tab
  /// (0 = Upcoming, 1 = Active Stays, 2 = Completed).
  void openHostReservations({int innerTab = 0}) {
    _hostTab = 1;
    _reservationsTab = innerTab;
    notifyListeners();
  }
}
