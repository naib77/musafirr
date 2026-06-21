/// The rental plan a listing can be booked by.
///
/// A listing offers any non-empty subset of these (see `Listing.offeredPlans`).
/// Rates are constrained so that hourly < daily < monthly among offered plans,
/// so the cheapest offered plan is normally the shortest offered unit.
enum DurationType { hourly, daily, monthly }

extension DurationTypeX on DurationType {
  /// Human-facing plan name, e.g. for toggles and segmented controls.
  String get label => switch (this) {
        DurationType.hourly => 'Hourly',
        DurationType.daily => 'Daily',
        DurationType.monthly => 'Monthly',
      };

  /// Unit shown next to a price in prose, e.g. "৳150/night".
  String get displayUnit => switch (this) {
        DurationType.hourly => 'hour',
        DurationType.daily => 'night',
        DurationType.monthly => 'month',
      };

  /// Compact unit for tight spaces, e.g. the card teaser "from ৳150/hr".
  String get shortUnit => switch (this) {
        DurationType.hourly => 'hr',
        DurationType.daily => 'day',
        DurationType.monthly => 'mo',
      };

  /// Database `pricing_unit` value — must match the DB enum: hour, day, month.
  String get pricingUnit => switch (this) {
        DurationType.hourly => 'hour',
        DurationType.daily => 'day',
        DurationType.monthly => 'month',
      };
}
