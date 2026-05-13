/// Exception thrown when attempting operations with mismatched currencies
class CurrencyMismatchException implements Exception {
  final String fromCurrency;
  final String toCurrency;
  final String operation;

  CurrencyMismatchException({
    required this.fromCurrency,
    required this.toCurrency,
    required this.operation,
  });

  @override
  String toString() =>
      'CurrencyMismatchException: Cannot $operation $fromCurrency with $toCurrency';
}

/// Exception thrown when an invalid amount is provided
class InvalidAmountException implements Exception {
  final double amount;
  final String reason;

  InvalidAmountException({
    required this.amount,
    required this.reason,
  });

  @override
  String toString() => 'InvalidAmountException: $amount - $reason';
}

/// Exception thrown when parsing fails
class CurrencyParseException implements Exception {
  final String input;
  final String? reason;

  CurrencyParseException({
    required this.input,
    this.reason,
  });

  @override
  String toString() =>
      'CurrencyParseException: Failed to parse "$input"${reason != null ? ' - $reason' : ''}';
}
