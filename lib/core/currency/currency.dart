/// Represents a currency with its properties
class Currency {
  /// ISO 4217 currency code (e.g., "BDT")
  final String code;

  /// Currency symbol (e.g., "৳")
  final String symbol;

  /// Full name of the currency
  final String name;

  /// Number of decimal places (typically 2)
  final int decimalPlaces;

  /// Locale for formatting (e.g., "bn_BD")
  final String locale;

  /// Whether symbol appears before the amount
  final bool symbolBefore;

  /// Subunit name (e.g., "paisa" for BDT)
  final String subunitName;

  /// Number of subunits in one unit (e.g., 100 paisa = 1 BDT)
  final int subunitsPerUnit;

  const Currency({
    required this.code,
    required this.symbol,
    required this.name,
    required this.decimalPlaces,
    required this.locale,
    required this.symbolBefore,
    required this.subunitName,
    required this.subunitsPerUnit,
  });

  /// Bangladesh Taka
  static const Currency BDT = Currency(
    code: 'BDT',
    symbol: '৳',
    name: 'Bangladeshi Taka',
    decimalPlaces: 2,
    locale: 'bn_BD',
    symbolBefore: true,
    subunitName: 'paisa',
    subunitsPerUnit: 100,
  );

  /// US Dollar (for future use)
  static const Currency USD = Currency(
    code: 'USD',
    symbol: '\$',
    name: 'US Dollar',
    decimalPlaces: 2,
    locale: 'en_US',
    symbolBefore: true,
    subunitName: 'cent',
    subunitsPerUnit: 100,
  );

  /// Get currency by code
  static Currency? fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'BDT':
        return BDT;
      case 'USD':
        return USD;
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Currency &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Currency($code)';
}
