import 'package:flutter/material.dart';

import '../models/facility.dart';

/// A named group of amenities, for the grouped picker on the create/edit
/// listing screens.
class FacilityGroup {
  const FacilityGroup({required this.title, required this.facilities});

  final String title;
  final List<Facility> facilities;
}

class FacilityCatalog {
  // Essentials
  static const wifi = Facility(name: 'Wi-Fi', icon: Icons.wifi);
  static const ac = Facility(name: 'AC', icon: Icons.ac_unit);
  static const bath = Facility(
    name: 'Attached Bath',
    icon: Icons.bathtub_outlined,
  );
  static const kitchen = Facility(
    name: 'Kitchen',
    icon: Icons.soup_kitchen_outlined,
  );
  static const hotWater = Facility(name: 'Hot Water', icon: Icons.hot_tub);
  static const drinkingWater =
      Facility(name: 'Drinking Water', icon: Icons.local_drink_outlined);

  // Features
  static const parking = Facility(
    name: 'Parking',
    icon: Icons.local_parking_outlined,
  );
  static const refrigerator =
      Facility(name: 'Refrigerator', icon: Icons.kitchen_outlined);
  static const washingMachine = Facility(
      name: 'Washing Machine', icon: Icons.local_laundry_service_outlined);
  static const tv = Facility(name: 'TV', icon: Icons.tv_outlined);
  static const workspace =
      Facility(name: 'Workspace', icon: Icons.desk_outlined);
  static const balcony =
      Facility(name: 'Balcony', icon: Icons.balcony_outlined);
  static const elevator =
      Facility(name: 'Elevator', icon: Icons.elevator_outlined);
  static const wardrobe =
      Facility(name: 'Wardrobe', icon: Icons.checkroom_outlined);
  static const prayerSpace =
      Facility(name: 'Prayer Space', icon: Icons.mosque_outlined);

  // Power (Bangladesh context — load-shedding matters to guests)
  static const generator =
      Facility(name: 'Backup Generator', icon: Icons.bolt_outlined);
  static const powerBackup = Facility(
      name: 'Power Backup (IPS)', icon: Icons.battery_charging_full_outlined);

  // Safety
  static const smokeAlarm =
      Facility(name: 'Smoke Alarm', icon: Icons.sensors_outlined);
  static const fireExtinguisher = Facility(
      name: 'Fire Extinguisher', icon: Icons.fire_extinguisher_outlined);
  static const firstAid =
      Facility(name: 'First Aid Kit', icon: Icons.medical_services_outlined);
  static const cctv =
      Facility(name: 'CCTV Security', icon: Icons.videocam_outlined);
  static const securityGuard =
      Facility(name: 'Security Guard', icon: Icons.shield_outlined);

  // Turf (migration 121). Parking, Drinking Water, CCTV Security, First Aid
  // Kit and Security Guard are NOT redefined here -- a turf reuses the rows
  // above, because two amenities meaning "parking" would split the amenity
  // filter in search_listings between them.
  static const floodlights =
      Facility(name: 'Floodlights', icon: Icons.light_mode_outlined);
  static const changingRoom =
      Facility(name: 'Changing Room', icon: Icons.checkroom_outlined);
  static const showers = Facility(name: 'Showers', icon: Icons.shower_outlined);
  static const washroom = Facility(name: 'Washroom', icon: Icons.wc_outlined);
  static const equipmentRental =
      Facility(name: 'Equipment Rental', icon: Icons.sports_soccer_outlined);
  static const coveredTurf =
      Facility(name: 'Covered Turf', icon: Icons.roofing_outlined);
  static const spectatorSeating =
      Facility(name: 'Spectator Seating', icon: Icons.event_seat_outlined);

  /// Amenities grouped for the picker UI. The `name` of each must match a row
  /// in the `facilities` table (see migrations 001 + 053 + 121) or it silently
  /// won't persist.
  static const groups = <FacilityGroup>[
    FacilityGroup(
      title: 'Essentials',
      facilities: [wifi, ac, bath, kitchen, hotWater, drinkingWater],
    ),
    FacilityGroup(
      title: 'Features',
      facilities: [
        parking,
        refrigerator,
        washingMachine,
        tv,
        workspace,
        balcony,
        elevator,
        wardrobe,
        prayerSpace,
      ],
    ),
    FacilityGroup(
      title: 'Power',
      facilities: [generator, powerBackup],
    ),
    FacilityGroup(
      title: 'Safety',
      facilities: [smokeAlarm, fireExtinguisher, firstAid, cctv, securityGuard],
    ),
  ];

  /// What a turf host is offered instead of [groups].
  ///
  /// A separate list rather than a filter over the stay one, because almost
  /// none of it overlaps: Wi-Fi, AC, Attached Bath, Kitchen, Hot Water,
  /// Refrigerator, Washing Machine, TV, Workspace, Balcony, Elevator, Wardrobe
  /// and Prayer Space are all meaningless on a football pitch. Showing a host
  /// twenty-two checkboxes of which four apply is how a form teaches people to
  /// skip it.
  static const turfGroups = <FacilityGroup>[
    FacilityGroup(
      title: 'The ground',
      facilities: [floodlights, coveredTurf, equipmentRental],
    ),
    FacilityGroup(
      title: 'Facilities',
      facilities: [
        changingRoom,
        showers,
        washroom,
        drinkingWater,
        spectatorSeating,
        parking,
      ],
    ),
    FacilityGroup(
      title: 'Safety',
      facilities: [firstAid, cctv, securityGuard],
    ),
  ];

  /// The groups a given listing type should offer.
  static List<FacilityGroup> groupsFor(bool isStay) =>
      isStay ? groups : turfGroups;

  /// Flat list of every host-selectable amenity (all groups, both shapes).
  ///
  /// Spans both so that an amenity a listing already carries still resolves
  /// after its type changes -- otherwise editing a turf back into a room would
  /// silently drop Floodlights from the saved set rather than showing it.
  ///
  /// **Deduplicated by name, and that is load-bearing.** Parking, Drinking
  /// Water and the three safety entries appear in both shapes, and the submit
  /// path filters this list by the selected names -- so a plain concatenation
  /// yields Parking twice, which reaches `listing_facilities` as two identical
  /// rows and is refused by its (listing_id, facility_id) unique index with
  /// 23505. The save fails entirely, for an amenity the host merely ticked.
  static final List<Facility> ownerSelectable = {
    for (final group in groups)
      for (final f in group.facilities) f.name: f,
    for (final group in turfGroups)
      for (final f in group.facilities) f.name: f,
  }.values.toList(growable: false);
}
