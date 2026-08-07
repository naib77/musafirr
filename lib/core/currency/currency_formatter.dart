import 'package:intl/intl.dart';

import 'currency.dart';
import 'currency_exceptions.dart';
import 'money.dart';

/// Service for formatting monetary amounts
///
/// Supports:
/// - Standard formatting with currency symbol
/// - Compact notation (K, L, Cr for BDT)
/// - Range formatting
/// - Per-unit formatting
class CurrencyFormatter {
  CurrencyFormatter._();

  static CurrencyFormatter? _instance;

  /// Singleton instance
  static CurrencyFormatter get instance {
    _instance ??= CurrencyFormatter._();
    return _instance!;
  }

  /// Default currency for the app
  Currency _defaultCurrency = Currency.bdt;

  /// Set default currency
  void setDefaultCurrency(Currency currency) {
    _defaultCurrency = currency;
  }

  /// Get default currency
  Currency get defaultCurrency => _defaultCurrency;

  /// Format a Money value
  ///
  /// Examples:
  /// - `format(Money.bdt(1500))` → "৳1,500"
  /// - `format(Money.bdt(1500), showSymbol: false)` → "1,500"
  /// - `format(Money.bdt(150000), useCompact: true)` → "৳1.5L"
  String format(
    Money money, {
    bool showSymbol = true,
    bool useCompact = false,
    bool showDecimal = true,
  }) {
    if (useCompact) {
      return _formatCompact(money, showSymbol: showSymbol);
    }
    return _formatStandard(money,
        showSymbol: showSymbol, showDecimal: showDecimal);
  }

  /// Standard formatting with commas
  String _formatStandard(
    Money money, {
    required bool showSymbol,
    required bool showDecimal,
  }) {
    final amount = money.amount;
    final currency = money.currency;

    String formatted;
    if (showDecimal && amount != amount.truncateToDouble()) {
      // Has decimal part
      formatted = NumberFormat('#,##0.00', 'en_US').format(amount);
    } else {
      // No decimal
      formatted = NumberFormat('#,##0', 'en_US').format(amount.truncate());
    }

    if (!showSymbol) {
      return formatted;
    }

    if (currency.symbolBefore) {
      return '${currency.symbol}$formatted';
    } else {
      return '$formatted${currency.symbol}';
    }
  }

  /// Compact formatting for large amounts
  ///
  /// For BDT:
  /// - < 1,000: normal (৳850)
  /// - 1,000 - 99,999: with K (৳12.5K)
  /// - 1,00,000 - 99,99,999: with L/Lakh (৳1.5L)
  /// - >= 1,00,00,000: with Cr/Crore (৳1.2Cr)
  String _formatCompact(Money money, {required bool showSymbol}) {
    final amount = money.amount;
    final currency = money.currency;

    String formatted;
    if (currency.code == 'BDT') {
      formatted = _formatBdtCompact(amount);
    } else {
      formatted = _formatGenericCompact(amount);
    }

    if (!showSymbol) {
      return formatted;
    }

    if (currency.symbolBefore) {
      return '${currency.symbol}$formatted';
    } else {
      return '$formatted${currency.symbol}';
    }
  }

  /// BDT-specific compact formatting (Lakh/Crore system)
  String _formatBdtCompact(double amount) {
    if (amount >= 10000000) {
      // Crore (1,00,00,000+)
      final crore = amount / 10000000;
      return '${_formatDecimal(crore)}Cr';
    } else if (amount >= 100000) {
      // Lakh (1,00,000+)
      final lakh = amount / 100000;
      return '${_formatDecimal(lakh)}L';
    } else if (amount >= 1000) {
      // Thousand
      final k = amount / 1000;
      return '${_formatDecimal(k)}K';
    } else {
      return NumberFormat('#,##0', 'en_US').format(amount.truncate());
    }
  }

  /// Generic compact formatting (K/M/B system)
  String _formatGenericCompact(double amount) {
    if (amount >= 1000000000) {
      return '${_formatDecimal(amount / 1000000000)}B';
    } else if (amount >= 1000000) {
      return '${_formatDecimal(amount / 1000000)}M';
    } else if (amount >= 1000) {
      return '${_formatDecimal(amount / 1000)}K';
    } else {
      return NumberFormat('#,##0', 'en_US').format(amount.truncate());
    }
  }

  /// Format decimal for compact display (max 1 decimal place)
  String _formatDecimal(double value) {
    if (value == value.truncateToDouble()) {
      return value.truncate().toString();
    }
    final formatted = value.toStringAsFixed(1);
    // Remove trailing .0
    if (formatted.endsWith('.0')) {
      return formatted.substring(0, formatted.length - 2);
    }
    return formatted;
  }

  /// Format a price range
  ///
  /// Example: `formatRange(Money.bdt(500), Money.bdt(1200))` → "৳500 - ৳1,200"
  String formatRange(Money min, Money max) {
    if (min.currency != max.currency) {
      throw CurrencyMismatchException(
        fromCurrency: min.currency.code,
        toCurrency: max.currency.code,
        operation: 'format range',
      );
    }
    return '${min.format()} - ${max.format()}';
  }

  /// Format price per unit
  ///
  /// Example: `formatPerUnit(Money.bdt(500), "night")` → "৳500/night"
  String formatPerUnit(Money money, String unit) {
    return '${money.format()}/$unit';
  }

  /// Format with strikethrough original price
  ///
  /// Returns a record with original and discounted formatted strings
  ({String original, String discounted, String savings}) formatWithDiscount(
    Money original,
    Money discounted,
  ) {
    final saved = original.subtract(discounted);
    return (
      original: original.format(),
      discounted: discounted.format(),
      savings: saved.format(),
    );
  }

  /// Parse a string into Money
  ///
  /// Supports formats like:
  /// - "1500"
  /// - "1,500"
  /// - "৳1,500"
  /// - "1500.50"
  Money? parse(String input, {Currency? currency}) {
    currency ??= _defaultCurrency;

    // Remove currency symbols and whitespace
    var cleaned = input.trim();
    cleaned = cleaned.replaceAll(currency.symbol, '');
    cleaned = cleaned.replaceAll(RegExp(r'[৳\$€£]'), '');
    cleaned = cleaned.replaceAll(',', '');
    cleaned = cleaned.trim();

    // Handle compact notation
    double multiplier = 1;
    if (cleaned.toUpperCase().endsWith('CR')) {
      multiplier = 10000000;
      cleaned = cleaned.substring(0, cleaned.length - 2);
    } else if (cleaned.toUpperCase().endsWith('L')) {
      multiplier = 100000;
      cleaned = cleaned.substring(0, cleaned.length - 1);
    } else if (cleaned.toUpperCase().endsWith('K')) {
      multiplier = 1000;
      cleaned = cleaned.substring(0, cleaned.length - 1);
    } else if (cleaned.toUpperCase().endsWith('M')) {
      multiplier = 1000000;
      cleaned = cleaned.substring(0, cleaned.length - 1);
    } else if (cleaned.toUpperCase().endsWith('B')) {
      multiplier = 1000000000;
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }

    final amount = double.tryParse(cleaned);
    if (amount == null) {
      return null;
    }

    try {
      return Money(amount * multiplier, currency);
    } catch (e) {
      return null;
    }
  }

  /// Parse or throw exception
  Money parseOrThrow(String input, {Currency? currency}) {
    final result = parse(input, currency: currency);
    if (result == null) {
      throw CurrencyParseException(input: input);
    }
    return result;
  }

  /// Reset singleton (for testing)
  static void reset() {
    _instance = null;
  }
}
