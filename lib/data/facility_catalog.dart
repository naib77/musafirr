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

  /// Amenities grouped for the picker UI. The `name` of each must match a row
  /// in the `facilities` table (see migrations 001 + 053) or it silently
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

  /// Flat list of every host-selectable amenity (all groups).
  static final List<Facility> ownerSelectable = [
    for (final group in groups) ...group.facilities,
  ];
}
