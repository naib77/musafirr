import 'facility.dart';
import 'listing_type.dart';

class OwnerRegistrationDraft {
  OwnerRegistrationDraft({
    required this.mobile,
    required this.title,
    required this.address,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.hourlyRate,
    required this.dailyRate,
    required this.monthlyRate,
    required this.facilities,
  });

  final String mobile;
  final String title;
  final String address;
  final ListingType type;
  final double latitude;
  final double longitude;
  final double hourlyRate;
  final double dailyRate;
  final double monthlyRate;
  final List<Facility> facilities;
}
