import 'package:flutter/material.dart';

import '../models/facility.dart';

class FacilityCatalog {
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
  static const parking = Facility(
    name: 'Parking',
    icon: Icons.local_parking_outlined,
  );

  static const ownerSelectable = [
    wifi,
    ac,
    bath,
    kitchen,
    parking,
  ];
}
