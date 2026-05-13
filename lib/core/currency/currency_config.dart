import 'currency.dart';
import 'money.dart';

/// Global configuration for currency handling in the app
class CurrencyConfig {
  CurrencyConfig._();

  /// Default currency for the application
  static const Currency defaultCurrency = Currency.BDT;

  /// Supported currencies
  static const List<Currency> supportedCurrencies = [
    Currency.BDT,
    // Currency.USD, // Enable when multi-currency is needed
  ];

  /// Maximum allowed amount (999 Crore in paisa)
  static const int maxAmountInMinorUnits = 999999999999; // ~999 Cr BDT

  /// Maximum discount percentage allowed
  static const double maxDiscountPercent = 50.0;

  /// Service fee percentage
  static const double serviceFeePercent = 5.0;

  /// Minimum booking amount in BDT
  static const double minBookingAmountValue = 100.0;

  /// Get minimum booking amount as Money
  static Money get minBookingAmount => Money.bdt(minBookingAmountValue);

  /// Whether to show decimal places for whole numbers
  static const bool showDecimalForWholeNumbers = false;

  /// Number format settings for BDT
  static const BdtFormatConfig bdtFormat = BdtFormatConfig();
}

/// BDT-specific formatting configuration
class BdtFormatConfig {
  const BdtFormatConfig();

  /// Threshold for using "K" notation
  int get thousandThreshold => 1000;

  /// Threshold for using "L" (Lakh) notation
  int get lakhThreshold => 100000;

  /// Threshold for using "Cr" (Crore) notation
  int get croreThreshold => 10000000;

  /// Whether to use Lakh/Crore notation
  bool get useLakhCroreNotation => true;

  /// Symbol position
  bool get symbolBefore => true;

  /// Decimal separator
  String get decimalSeparator => '.';

  /// Thousand separator
  String get thousandSeparator => ',';
}
