import '../services/contact_phone.dart';
import 'facility.dart';
import 'hotel_details.dart';
import 'listing.dart';
import 'listing_type.dart';

/// A hotel as a whole (`public.properties`, migration 153). Its room types
/// are ordinary listings with `property_id` set; the database copies the
/// hotel facts below onto each of them on every write
/// (`a_listing_property_inherit` / `fn_property_push_down`), so a guest read
/// of a room type never needs this row.
///
/// The exact address is NOT here: like a listing's, it lives in a gated side
/// table ([PropertyAddress]) and is copied into each room type's
/// `listing_addresses` row, so the guest reveal path is unchanged.
class Property {
  const Property({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.area,
    this.city,
    this.country,
    this.postalCode,
    this.landmark,
    this.latitude,
    this.longitude,
    this.checkInTime,
    this.checkOutTime,
    this.hotelDetails = const HotelDetails(),
    this.imageUrls = const [],
    this.facilities = const [],
  });

  /// [facilities] is parsed by the repository, which owns the name -> catalog
  /// lookup (the same one listings use), from the embedded
  /// `property_facilities` rows.
  factory Property.fromJson(Map<String, dynamic> json,
      {List<Facility> facilities = const []}) {
    return Property(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      area: json['area'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      postalCode: json['postal_code'] as String?,
      landmark: json['landmark'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      checkInTime: json['check_in_time'] as String?,
      checkOutTime: json['check_out_time'] as String?,
      hotelDetails: HotelDetails.fromJson(json),
      imageUrls: (json['image_urls'] as List?)?.cast<String>() ?? const [],
      facilities: facilities,
    );
  }

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? area;
  final String? city;
  final String? country;
  final String? postalCode;
  final String? landmark;

  /// Already snapped to the public grid by `trg_property_normalise`; the
  /// precise point is in [PropertyAddress].
  final double? latitude;
  final double? longitude;
  final String? checkInTime;
  final String? checkOutTime;
  final HotelDetails hotelDetails;
  final List<String> imageUrls;

  /// The hotel-wide amenities (`property_facilities`, 155). The database
  /// copies them onto every room type's `listing_facilities`, which is what
  /// search filters on; this is the hotel form's copy and the hotel page's
  /// "once per hotel" list. Not in [toJson]: saved by
  /// [MusafirRepository.createProperty]/`updateProperty` as rows.
  final List<Facility> facilities;

  /// The area line a guest sees, built the same way a listing's is.
  String get publicAddress =>
      Listing.composeAddress(area: area, city: city).trim();

  /// The write shape. `owner_id` only on insert: the normalise trigger
  /// refuses a change (hint `property_owner_fixed`), and sending the same
  /// value on update would be noise at best.
  Map<String, dynamic> toJson({bool includeOwner = false}) => {
        if (includeOwner) 'owner_id': ownerId,
        'name': name,
        'description': description,
        'area': area,
        'city': city,
        'country': country,
        'postal_code': postalCode,
        'landmark': landmark,
        'latitude': latitude,
        'longitude': longitude,
        'check_in_time': checkInTime,
        'check_out_time': checkOutTime,
        ...hotelDetails.toJson(),
        'image_urls': imageUrls,
      };

  /// Seeds a new room type of this hotel. Only what a room type cannot be
  /// without -- the database overwrites the copied facts anyway, but the
  /// local optimistic copy should already look right.
  Listing seedRoomType({required String tempId, required String ownerName}) {
    return Listing(
      id: tempId,
      propertyId: id,
      ownerName: ownerName,
      title: '',
      address: publicAddress,
      type: ListingType.hotel,
      latitude: latitude ?? 0,
      longitude: longitude ?? 0,
      facilities: const [],
      available: true,
      hostId: ownerId,
      city: city,
      country: country,
      area: area,
      postalCode: postalCode,
      landmark: landmark,
      hotelDetails: hotelDetails,
      houseRules: HouseRules(
        checkInTime: checkInTime,
        checkOutTime: checkOutTime,
      ),
    );
  }
}

/// The door-level half of a [Property] (`public.property_addresses`).
/// Owner/admin only by RLS; a trigger copies it into every room type's
/// `listing_addresses`, which is what a guest with a booking can reveal.
class PropertyAddress {
  const PropertyAddress({
    this.houseNo,
    this.street,
    this.exactAddress,
    this.latitude,
    this.longitude,
    this.contactPhones = const [],
  });

  factory PropertyAddress.fromJson(Map<String, dynamic> json) {
    return PropertyAddress(
      houseNo: json['house_no'] as String?,
      street: json['street'] as String?,
      exactAddress: json['exact_address'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      contactPhones: contactPhonesFromJson(json['contact_phones']),
    );
  }

  final String? houseNo;
  final String? street;
  final String? exactAddress;
  final double? latitude;
  final double? longitude;

  /// 160/162. The hotel's contact numbers (`+880…`), copied onto every room
  /// type's address row by the database, the way the address itself is.
  final List<String> contactPhones;

  Map<String, dynamic> toJson(String propertyId) => {
        'property_id': propertyId,
        'house_no': houseNo,
        'street': street,
        'exact_address': exactAddress,
        'latitude': latitude,
        'longitude': longitude,
        'contact_phones': contactPhones.isEmpty ? null : contactPhones,
      };
}

/// What to tell the host when a hotel or room write is refused, keyed by the
/// hint 153 raises (never the message text -- database-booking-and-search.md).
String propertyRefusalMessage(String? hint) => switch (hint) {
      'room_label_taken' => 'Another room in this hotel already has that name.',
      'room_label_duplicate' => 'The same room name is listed twice.',
      'room_label_invalid' => 'Room names can be at most 40 characters.',
      'unit_count_range' =>
        'A room type keeps at least one room, and at most 500.',
      'units_in_use' => 'That room has an upcoming booking. Move or cancel '
          'the booking first.',
      'unit_move_other_property' =>
        'A room can only move to another room type of the same hotel.',
      'unit_not_found' || 'listing_not_found' => 'That room no longer exists.',
      'not_listing_owner' ||
      'property_owner_mismatch' =>
        'Only the hotel\'s host can change its rooms.',
      'property_fixed' => 'A room type cannot leave its hotel.',
      'property_child_type' => 'Only hotel rooms can belong to a hotel.',
      // 156: deleting a room type or a whole hotel.
      'listing_has_bookings' => 'This room type has upcoming or current '
          'bookings. Cancel or complete them before deleting.',
      'property_has_bookings' => 'This hotel has upcoming or current '
          'bookings. Cancel or complete them before deleting.',
      'listing_has_history' || 'property_has_history' => 'This has payment '
          'history and can\'t be deleted. Hide the room types instead -- '
          'guests won\'t see them, and your records stay intact.',
      'property_not_found' => 'That hotel no longer exists.',
      'not_a_room_type' => 'That listing is not part of a hotel.',
      _ => 'Could not save. Please try again.',
    };

/// The listing was created but its rooms were not (a label taken elsewhere
/// in the hotel, say). Distinct from a failed create so the wizard does not
/// invite a retry that would insert the listing twice.
class RoomsNotSavedException implements Exception {
  const RoomsNotSavedException(this.listingId, this.cause);

  final String listingId;
  final Object cause;

  @override
  String toString() => 'RoomsNotSavedException($listingId): $cause';
}
