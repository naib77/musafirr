import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:musafir/models/user.dart';
import 'package:musafir/models/listing.dart';
import 'package:musafir/models/search_filters.dart';
import 'package:musafir/models/booking.dart';
import 'package:musafir/models/review.dart';
import 'package:musafir/models/message.dart';
import 'package:musafir/models/conversation.dart';
import 'package:musafir/repositories/musafir_repository.dart';
import 'package:musafir/state/auth_state.dart';

/// Test wrapper widget with common providers
class TestApp extends StatelessWidget {
  const TestApp({
    super.key,
    required this.child,
    this.authState,
    this.repository,
    this.overrides = const [],
  });

  final Widget child;
  final AuthStateNotifier? authState;
  final MusafirRepository? repository;
  final List<Override> overrides;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          if (authState != null)
            ChangeNotifierProvider<AuthStateNotifier>.value(value: authState!),
          if (repository != null)
            Provider<MusafirRepository>.value(value: repository!),
          ...overrides.map((o) => o.provider),
        ],
        child: child,
      ),
    );
  }
}

/// Provider override helper
class Override {
  const Override({required this.provider});
  final ProviderSingleChildWidget provider;
}

/// Pump widget with all setup
extension TestWidgetExtension on WidgetTester {
  /// Pump a widget wrapped in TestApp
  Future<void> pumpTestApp(
    Widget widget, {
    AuthStateNotifier? authState,
    MusafirRepository? repository,
    List<Override> overrides = const [],
    Duration? duration,
  }) async {
    await pumpWidget(
      TestApp(
        authState: authState,
        repository: repository,
        overrides: overrides,
        child: widget,
      ),
    );
    if (duration != null) {
      await pump(duration);
    }
  }

  /// Pump and settle with timeout
  Future<void> pumpAndSettleWithTimeout([
    Duration timeout = const Duration(seconds: 10),
  ]) async {
    await pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      timeout,
    );
  }

  /// Wait for async operations
  Future<void> waitFor(
    Future<void> Function() action, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    await action();
    await pumpAndSettleWithTimeout(timeout);
  }
}

/// Mock repository implementation
class MockMusafirRepository implements MusafirRepository {
  MockMusafirRepository({
    this.users = const [],
    this.listings = const [],
    this.bookings = const [],
    this.reviews = const [],
    this.conversations = const [],
    this.messages = const [],
    this.shouldFail = false,
    this.delay = Duration.zero,
  });

  List<User> users;
  @override
  List<Listing> listings;
  @override
  List<Booking> bookings;
  List<Review> reviews;
  List<Conversation> conversations;
  List<Message> messages;
  bool shouldFail;
  Duration delay;

  final _callLog = <String>[];
  List<String> get callLog => List.unmodifiable(_callLog);

  void clearCallLog() => _callLog.clear();

  Future<T> _execute<T>(String method, T Function() action) async {
    _callLog.add(method);
    if (delay > Duration.zero) {
      await Future.delayed(delay);
    }
    if (shouldFail) {
      throw Exception('Mock failure: $method');
    }
    return action();
  }

  // User methods
  @override
  Future<User?> getUserById(String id) =>
      _execute('getUserById', () => users.where((u) => u.id == id).firstOrNull);

  @override
  Future<User?> getUserByEmail(String email) =>
      _execute('getUserByEmail', () => users.where((u) => u.email == email).firstOrNull);

  @override
  Future<User> createUser(User user) => _execute('createUser', () {
        users = [...users, user];
        return user;
      });

  @override
  Future<User> updateUser(User user) => _execute('updateUser', () {
        users = users.map((u) => u.id == user.id ? user : u).toList();
        return user;
      });

  @override
  Future<void> deleteUser(String id) => _execute('deleteUser', () {
        users = users.where((u) => u.id != id).toList();
      });

  // Listing methods
  @override
  Future<List<Listing>> getListings({
    String? hostId,
    ListingType? type,
    String? city,
    double? minPrice,
    double? maxPrice,
    int? guests,
    int limit = 20,
    int offset = 0,
  }) =>
      _execute('getListings', () {
        var result = listings;
        if (hostId != null) result = result.where((l) => l.hostId == hostId).toList();
        if (type != null) result = result.where((l) => l.type == type).toList();
        if (city != null) result = result.where((l) => l.address.city == city).toList();
        if (minPrice != null) result = result.where((l) => l.pricePerNight >= minPrice).toList();
        if (maxPrice != null) result = result.where((l) => l.pricePerNight <= maxPrice).toList();
        if (guests != null) result = result.where((l) => l.maxGuests >= guests).toList();
        return result.skip(offset).take(limit).toList();
      });

  @override
  Future<Listing?> getListingById(String id) =>
      _execute('getListingById', () => listings.where((l) => l.id == id).firstOrNull);

  @override
  Future<Listing> createListing(Listing listing) => _execute('createListing', () {
        listings = [...listings, listing];
        return listing;
      });

  @override
  Future<Listing> updateListing(Listing listing) => _execute('updateListing', () {
        listings = listings.map((l) => l.id == listing.id ? listing : l).toList();
        return listing;
      });

  @override
  Future<void> deleteListing(String id) => _execute('deleteListing', () {
        listings = listings.where((l) => l.id != id).toList();
      });

  @override
  Future<void> setListingAvailability(String id, bool available) =>
      _execute('setListingAvailability', () {
        listings = listings
            .map((l) => l.id == id ? l.copyWith(available: available) : l)
            .toList();
      });

  @override
  Future<List<Listing>> searchListings(String query) =>
      _execute('searchListings', () => listings
          .where((l) => l.title.toLowerCase().contains(query.toLowerCase()))
          .toList());

  @override
  Future<List<Listing>> searchListingsFromDb(
    SearchFilters filters, {
    int limit = 50,
    int offset = 0,
  }) =>
      _execute('searchListingsFromDb', () => listings);

  @override
  Future<List<Listing>> getNearbyListings(double lat, double lng, double radiusKm) =>
      _execute('getNearbyListings', () => listings);

  // Booking methods
  @override
  Future<List<Booking>> getBookings({
    String? guestId,
    String? hostId,
    String? listingId,
    BookingStatus? status,
    int limit = 20,
    int offset = 0,
  }) =>
      _execute('getBookings', () {
        var result = bookings;
        if (guestId != null) result = result.where((b) => b.guestId == guestId).toList();
        if (listingId != null) result = result.where((b) => b.listingId == listingId).toList();
        if (status != null) result = result.where((b) => b.status == status).toList();
        return result.skip(offset).take(limit).toList();
      });

  @override
  Future<Booking?> getBookingById(String id) =>
      _execute('getBookingById', () => bookings.where((b) => b.id == id).firstOrNull);

  @override
  Future<Booking> createBooking(Booking booking) => _execute('createBooking', () {
        bookings = [...bookings, booking];
        return booking;
      });

  @override
  Future<Booking> updateBooking(Booking booking) => _execute('updateBooking', () {
        bookings = bookings.map((b) => b.id == booking.id ? booking : b).toList();
        return booking;
      });

  @override
  Future<void> deleteBooking(String id) => _execute('deleteBooking', () {
        bookings = bookings.where((b) => b.id != id).toList();
      });

  @override
  Future<List<DateTimeRange>> getUnavailableDates(String listingId) =>
      _execute('getUnavailableDates', () => []);

  // Review methods
  @override
  Future<List<Review>> getReviews({
    String? listingId,
    String? authorId,
    int limit = 20,
    int offset = 0,
  }) =>
      _execute('getReviews', () {
        var result = reviews;
        if (listingId != null) result = result.where((r) => r.listingId == listingId).toList();
        if (authorId != null) result = result.where((r) => r.authorId == authorId).toList();
        return result.skip(offset).take(limit).toList();
      });

  @override
  Future<Review> createReview(Review review) => _execute('createReview', () {
        reviews = [...reviews, review];
        return review;
      });

  @override
  Future<Review> updateReview(Review review) => _execute('updateReview', () {
        reviews = reviews.map((r) => r.id == review.id ? review : r).toList();
        return review;
      });

  @override
  Future<void> deleteReview(String id) => _execute('deleteReview', () {
        reviews = reviews.where((r) => r.id != id).toList();
      });

  // Message methods
  @override
  Future<List<Conversation>> getConversations(String userId) =>
      _execute('getConversations', () => conversations
          .where((c) => c.participantIds.contains(userId))
          .toList());

  @override
  Future<Conversation?> getConversation(String id) =>
      _execute('getConversation', () => conversations.where((c) => c.id == id).firstOrNull);

  @override
  Future<Conversation> createConversation(Conversation conversation) =>
      _execute('createConversation', () {
        conversations = [...conversations, conversation];
        return conversation;
      });

  @override
  Future<List<Message>> getMessages(String conversationId, {int limit = 50, int offset = 0}) =>
      _execute('getMessages', () => messages
          .where((m) => m.conversationId == conversationId)
          .skip(offset)
          .take(limit)
          .toList());

  @override
  Future<Message> sendMessage(Message message) => _execute('sendMessage', () {
        messages = [...messages, message];
        return message;
      });

  @override
  Future<void> markMessageAsRead(String messageId) =>
      _execute('markMessageAsRead', () {});

  @override
  Stream<Message> subscribeToMessages(String conversationId) =>
      Stream.fromIterable(messages.where((m) => m.conversationId == conversationId));

  // Wishlist methods
  @override
  Future<List<Listing>> getWishlist(String userId) =>
      _execute('getWishlist', () => []);

  @override
  Future<void> addToWishlist(String userId, String listingId) =>
      _execute('addToWishlist', () {});

  @override
  Future<void> removeFromWishlist(String userId, String listingId) =>
      _execute('removeFromWishlist', () {});

  @override
  Future<bool> isInWishlist(String userId, String listingId) =>
      _execute('isInWishlist', () => false);
}

/// Test data factory
class TestData {
  TestData._();

  static User createUser({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? avatarUrl,
    bool isHost = false,
    DateTime? createdAt,
  }) =>
      User(
        id: id ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
        email: email ?? 'test@example.com',
        name: name ?? 'Test User',
        phone: phone,
        avatarUrl: avatarUrl,
        isHost: isHost,
        createdAt: createdAt ?? DateTime.now(),
      );

  static Listing createListing({
    String? id,
    String? hostId,
    String? title,
    String? description,
    ListingType type = ListingType.apartment,
    double pricePerNight = 100.0,
    int maxGuests = 4,
    int bedrooms = 2,
    int bathrooms = 1,
    List<String> amenities = const [],
    List<String> images = const [],
    Address? address,
    double rating = 4.5,
    int reviewCount = 10,
    bool isActive = true,
    DateTime? createdAt,
  }) =>
      Listing(
        id: id ?? 'listing_${DateTime.now().millisecondsSinceEpoch}',
        hostId: hostId ?? 'host_1',
        title: title ?? 'Test Listing',
        description: description ?? 'A test listing description',
        type: type,
        pricePerNight: pricePerNight,
        maxGuests: maxGuests,
        bedrooms: bedrooms,
        bathrooms: bathrooms,
        amenities: amenities,
        images: images,
        address: address ?? createAddress(),
        rating: rating,
        reviewCount: reviewCount,
        isActive: isActive,
        createdAt: createdAt ?? DateTime.now(),
      );

  static Address createAddress({
    String? street,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    double latitude = 23.8103,
    double longitude = 90.4125,
  }) =>
      Address(
        street: street ?? '123 Test Street',
        city: city ?? 'Dhaka',
        state: state ?? 'Dhaka',
        country: country ?? 'Bangladesh',
        postalCode: postalCode ?? '1000',
        latitude: latitude,
        longitude: longitude,
      );

  static Booking createBooking({
    String? id,
    String? listingId,
    String? guestId,
    DateTime? checkIn,
    DateTime? checkOut,
    int guests = 2,
    double totalPrice = 200.0,
    BookingStatus status = BookingStatus.pending,
    String? specialRequests,
    DateTime? createdAt,
  }) {
    final now = DateTime.now();
    return Booking(
      id: id ?? 'booking_${now.millisecondsSinceEpoch}',
      listingId: listingId ?? 'listing_1',
      guestId: guestId ?? 'guest_1',
      checkIn: checkIn ?? now.add(const Duration(days: 7)),
      checkOut: checkOut ?? now.add(const Duration(days: 10)),
      guests: guests,
      totalPrice: totalPrice,
      status: status,
      specialRequests: specialRequests,
      createdAt: createdAt ?? now,
    );
  }

  static Review createReview({
    String? id,
    String? listingId,
    String? authorId,
    String? authorName,
    String? authorAvatar,
    double rating = 4.5,
    String? comment,
    DateTime? createdAt,
  }) =>
      Review(
        id: id ?? 'review_${DateTime.now().millisecondsSinceEpoch}',
        listingId: listingId ?? 'listing_1',
        authorId: authorId ?? 'user_1',
        authorName: authorName ?? 'Test Reviewer',
        authorAvatar: authorAvatar,
        rating: rating,
        comment: comment ?? 'Great place to stay!',
        createdAt: createdAt ?? DateTime.now(),
      );

  static Conversation createConversation({
    String? id,
    List<String>? participantIds,
    String? listingId,
    Message? lastMessage,
    int unreadCount = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now();
    return Conversation(
      id: id ?? 'conv_${now.millisecondsSinceEpoch}',
      participantIds: participantIds ?? ['user_1', 'user_2'],
      listingId: listingId,
      lastMessage: lastMessage,
      unreadCount: unreadCount,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  static Message createMessage({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    MessageType type = MessageType.text,
    bool isRead = false,
    DateTime? createdAt,
  }) =>
      Message(
        id: id ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
        conversationId: conversationId ?? 'conv_1',
        senderId: senderId ?? 'user_1',
        content: content ?? 'Test message',
        type: type,
        isRead: isRead,
        createdAt: createdAt ?? DateTime.now(),
      );
}

/// Golden test helpers
Future<void> expectGolden(
  WidgetTester tester,
  Widget widget,
  String goldenFileName,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(child: widget),
    ),
  );
  await expectLater(
    find.byType(RepaintBoundary),
    matchesGoldenFile('goldens/$goldenFileName.png'),
  );
}

/// Async test helper
Future<void> expectLaterWithTimeout<T>(
  Future<T> actual,
  Matcher matcher, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  await expectLater(
    actual.timeout(timeout),
    matcher,
  );
}

/// Stream test helpers
extension StreamTestExtension<T> on Stream<T> {
  /// Collect stream values for testing
  Future<List<T>> collectValues({
    int count = 10,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final values = <T>[];
    await for (final value in take(count).timeout(timeout)) {
      values.add(value);
    }
    return values;
  }
}

/// Mock callbacks tracker
class CallbackTracker {
  final _calls = <String, List<List<dynamic>>>{};

  void track(String name, [List<dynamic> args = const []]) {
    _calls.putIfAbsent(name, () => []).add(args);
  }

  int callCount(String name) => _calls[name]?.length ?? 0;

  List<List<dynamic>> callsFor(String name) => _calls[name] ?? [];

  bool wasCalled(String name) => callCount(name) > 0;

  bool wasCalledWith(String name, List<dynamic> args) {
    return _calls[name]?.any((call) => _listEquals(call, args)) ?? false;
  }

  void clear() => _calls.clear();

  bool _listEquals(List a, List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Fake async helper for testing timers and delays
class FakeAsync {
  final _timers = <Timer>[];
  Duration _elapsed = Duration.zero;

  /// Create a fake timer
  Timer createTimer(Duration duration, void Function() callback) {
    final timer = _FakeTimer(duration, callback, _elapsed);
    _timers.add(timer);
    return timer;
  }

  /// Advance time
  void elapse(Duration duration) {
    _elapsed += duration;
    for (final timer in _timers) {
      if (timer is _FakeTimer && !timer._cancelled) {
        if (_elapsed >= timer._createdAt + timer._duration) {
          timer._callback();
          timer._cancelled = true;
        }
      }
    }
    _timers.removeWhere((t) => t is _FakeTimer && t._cancelled);
  }

  /// Flush all pending timers
  void flushTimers() {
    while (_timers.isNotEmpty) {
      final next = _timers
          .whereType<_FakeTimer>()
          .where((t) => !t._cancelled)
          .reduce((a, b) =>
              a._createdAt + a._duration < b._createdAt + b._duration ? a : b);
      elapse(next._createdAt + next._duration - _elapsed);
    }
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._duration, this._callback, this._createdAt);

  final Duration _duration;
  final void Function() _callback;
  final Duration _createdAt;
  bool _cancelled = false;

  @override
  void cancel() => _cancelled = true;

  @override
  bool get isActive => !_cancelled;

  @override
  int get tick => 1;
}
