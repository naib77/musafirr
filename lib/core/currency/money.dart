import 'currency.dart';
import 'currency_exceptions.dart';
import 'currency_formatter.dart';

/// Immutable value object representing a monetary amount
///
/// Stores amounts in the smallest currency unit (e.g., paisa for BDT)
/// to avoid floating-point precision issues.
class Money implements Comparable<Money> {
  /// Amount in smallest currency unit (e.g., paisa)
  final int amountInMinorUnits;

  /// The currency of this money
  final Currency currency;

  /// Private constructor - use factory constructors
  const Money._({
    required this.amountInMinorUnits,
    required this.currency,
  });

  /// Create Money from a decimal amount (e.g., 150.50 BDT)
  factory Money(double amount, Currency currency) {
    if (amount.isNaN || amount.isInfinite) {
      throw InvalidAmountException(
        amount: amount,
        reason: 'Amount must be a valid number',
      );
    }
    if (amount < 0) {
      throw InvalidAmountException(
        amount: amount,
        reason: 'Amount cannot be negative',
      );
    }

    final minorUnits = (amount * currency.subunitsPerUnit).round();
    return Money._(amountInMinorUnits: minorUnits, currency: currency);
  }

  /// Create Money in BDT from a decimal amount
  factory Money.bdt(double amount) => Money(amount, Currency.bdt);

  /// Create Money from minor units (e.g., paisa)
  factory Money.fromMinorUnits(int minorUnits, Currency currency) {
    if (minorUnits < 0) {
      throw InvalidAmountException(
        amount: minorUnits.toDouble(),
        reason: 'Minor units cannot be negative',
      );
    }
    return Money._(amountInMinorUnits: minorUnits, currency: currency);
  }

  /// Create zero amount
  factory Money.zero(Currency currency) =>
      Money._(amountInMinorUnits: 0, currency: currency);

  /// Create zero BDT
  static Money get zeroBdt => Money.zero(Currency.bdt);

  /// Get amount as decimal (e.g., 150.50)
  double get amount => amountInMinorUnits / currency.subunitsPerUnit;

  /// Check if amount is zero
  bool get isZero => amountInMinorUnits == 0;

  /// Check if amount is positive
  bool get isPositive => amountInMinorUnits > 0;

  // ============ Arithmetic Operations ============

  /// Add two Money values (must be same currency)
  Money add(Money other) {
    _ensureSameCurrency(other, 'add');
    return Money._(
      amountInMinorUnits: amountInMinorUnits + other.amountInMinorUnits,
      currency: currency,
    );
  }

  /// Subtract Money from this (must be same currency)
  Money subtract(Money other) {
    _ensureSameCurrency(other, 'subtract');
    final result = amountInMinorUnits - other.amountInMinorUnits;
    if (result < 0) {
      throw InvalidAmountException(
        amount: result.toDouble(),
        reason: 'Subtraction would result in negative amount',
      );
    }
    return Money._(amountInMinorUnits: result, currency: currency);
  }

  /// Multiply by a factor
  Money multiply(double factor) {
    if (factor < 0) {
      throw InvalidAmountException(
        amount: factor,
        reason: 'Multiplication factor cannot be negative',
      );
    }
    final result = (amountInMinorUnits * factor).round();
    return Money._(amountInMinorUnits: result, currency: currency);
  }

  /// Divide by a factor
  Money divide(double divisor) {
    if (divisor <= 0) {
      throw InvalidAmountException(
        amount: divisor,
        reason: 'Divisor must be positive',
      );
    }
    final result = (amountInMinorUnits / divisor).round();
    return Money._(amountInMinorUnits: result, currency: currency);
  }

  /// Calculate percentage of this amount
  Money percentage(double percent) {
    return multiply(percent / 100);
  }

  // ============ Comparison Operations ============

  @override
  int compareTo(Money other) {
    _ensureSameCurrency(other, 'compare');
    return amountInMinorUnits.compareTo(other.amountInMinorUnits);
  }

  bool operator >(Money other) => compareTo(other) > 0;
  bool operator <(Money other) => compareTo(other) < 0;
  bool operator >=(Money other) => compareTo(other) >= 0;
  bool operator <=(Money other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Money &&
          runtimeType == other.runtimeType &&
          amountInMinorUnits == other.amountInMinorUnits &&
          currency == other.currency;

  @override
  int get hashCode => Object.hash(amountInMinorUnits, currency);

  // ============ Formatting ============

  /// Format with default settings
  String format({
    bool showSymbol = true,
    bool useCompact = false,
    bool showDecimal = true,
  }) {
    return CurrencyFormatter.instance.format(
      this,
      showSymbol: showSymbol,
      useCompact: useCompact,
      showDecimal: showDecimal,
    );
  }

  /// Format as compact string (e.g., "৳1.5L")
  String toCompactString() => format(useCompact: true, showDecimal: false);

  /// Format without symbol
  String toPlainString() => format(showSymbol: false);

  @override
  String toString() => format();

  // ============ Utility ============

  /// Create a copy with different amount
  Money copyWith({double? amount, int? minorUnits}) {
    if (amount != null) {
      return Money(amount, currency);
    }
    if (minorUnits != null) {
      return Money.fromMinorUnits(minorUnits, currency);
    }
    return this;
  }

  /// Ensure same currency for operations
  void _ensureSameCurrency(Money other, String operation) {
    if (currency != other.currency) {
      throw CurrencyMismatchException(
        fromCurrency: currency.code,
        toCurrency: other.currency.code,
        operation: operation,
      );
    }
  }

  /// Convert to Map (for JSON serialization)
  Map<String, dynamic> toJson() => {
        'amount': amount,
        'currency': currency.code,
        'minorUnits': amountInMinorUnits,
      };

  /// Create from Map (for JSON deserialization)
  factory Money.fromJson(Map<String, dynamic> json) {
    final currencyCode = json['currency'] as String? ?? 'BDT';
    final currency = Currency.fromCode(currencyCode) ?? Currency.bdt;

    if (json.containsKey('minorUnits')) {
      return Money.fromMinorUnits(json['minorUnits'] as int, currency);
    }
    return Money(json['amount'] as double, currency);
  }
}

/// Extension for easy Money creation from numbers
extension MoneyExtension on num {
  Money get bdt => Money.bdt(toDouble());
  Money asCurrency(Currency currency) => Money(toDouble(), currency);
}
