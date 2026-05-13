import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/currency/currency.dart';
import '../core/currency/money.dart';

/// Text field for entering monetary amounts
class PriceInputField extends StatefulWidget {
  /// Controller for the text field
  final TextEditingController? controller;

  /// Currency for display
  final Currency currency;

  /// Label text
  final String label;

  /// Hint text
  final String? hint;

  /// Callback when value changes
  final ValueChanged<Money?>? onChanged;

  /// Validator
  final String? Function(Money?)? validator;

  /// Whether the field is enabled
  final bool enabled;

  /// Minimum allowed value
  final Money? minValue;

  /// Maximum allowed value
  final Money? maxValue;

  /// Text input action
  final TextInputAction? textInputAction;

  /// Callback when submitted
  final VoidCallback? onSubmitted;

  /// Helper text
  final String? helperText;

  const PriceInputField({
    super.key,
    this.controller,
    this.currency = Currency.BDT,
    required this.label,
    this.hint,
    this.onChanged,
    this.validator,
    this.enabled = true,
    this.minValue,
    this.maxValue,
    this.textInputAction,
    this.onSubmitted,
    this.helperText,
  });

  @override
  State<PriceInputField> createState() => _PriceInputFieldState();
}

class _PriceInputFieldState extends State<PriceInputField> {
  late TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  Money? _parseValue() {
    final text = _controller.text.trim();
    if (text.isEmpty) return null;

    final value = double.tryParse(text.replaceAll(',', ''));
    if (value == null || value < 0) return null;

    return Money(value, widget.currency);
  }

  void _onChanged(String value) {
    final money = _parseValue();

    // Run validation
    String? error;
    if (widget.validator != null) {
      error = widget.validator!(money);
    }

    // Check bounds
    if (error == null && money != null) {
      if (widget.minValue != null && money < widget.minValue!) {
        error = 'Minimum is ${widget.minValue!.format()}';
      } else if (widget.maxValue != null && money > widget.maxValue!) {
        error = 'Maximum is ${widget.maxValue!.format()}';
      }
    }

    setState(() {
      _errorText = error;
    });

    widget.onChanged?.call(money);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextFormField(
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: widget.textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
        _ThousandsSeparatorInputFormatter(),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint ?? '0',
        helperText: widget.helperText,
        errorText: _errorText,
        border: const OutlineInputBorder(),
        prefixIcon: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.currency.symbol,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
      onChanged: _onChanged,
      onFieldSubmitted: (_) => widget.onSubmitted?.call(),
      validator: (value) {
        final money = _parseValue();
        if (widget.validator != null) {
          return widget.validator!(money);
        }
        return null;
      },
    );
  }
}

/// Input formatter that adds thousand separators
class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Remove existing commas
    final text = newValue.text.replaceAll(',', '');

    // Handle decimal
    final parts = text.split('.');
    final integerPart = parts[0];
    final decimalPart = parts.length > 1 ? '.${parts[1]}' : '';

    // Format integer part with commas
    final buffer = StringBuffer();
    final length = integerPart.length;

    for (var i = 0; i < length; i++) {
      if (i > 0 && (length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(integerPart[i]);
    }

    final formatted = buffer.toString() + decimalPart;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Multiple price inputs for hourly/daily/monthly rates
class PriceRateInputs extends StatelessWidget {
  final TextEditingController? hourlyController;
  final TextEditingController? dailyController;
  final TextEditingController? monthlyController;
  final Currency currency;
  final bool hourlyEnabled;
  final bool dailyEnabled;
  final bool monthlyEnabled;
  final ValueChanged<Money?>? onHourlyChanged;
  final ValueChanged<Money?>? onDailyChanged;
  final ValueChanged<Money?>? onMonthlyChanged;

  const PriceRateInputs({
    super.key,
    this.hourlyController,
    this.dailyController,
    this.monthlyController,
    this.currency = Currency.BDT,
    this.hourlyEnabled = true,
    this.dailyEnabled = true,
    this.monthlyEnabled = true,
    this.onHourlyChanged,
    this.onDailyChanged,
    this.onMonthlyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hourlyEnabled)
          PriceInputField(
            controller: hourlyController,
            currency: currency,
            label: 'Hourly Rate',
            hint: 'Price per hour',
            onChanged: onHourlyChanged,
            textInputAction: TextInputAction.next,
          ),
        if (hourlyEnabled && (dailyEnabled || monthlyEnabled))
          const SizedBox(height: 16),
        if (dailyEnabled)
          PriceInputField(
            controller: dailyController,
            currency: currency,
            label: 'Daily Rate',
            hint: 'Price per day',
            onChanged: onDailyChanged,
            textInputAction: TextInputAction.next,
          ),
        if (dailyEnabled && monthlyEnabled) const SizedBox(height: 16),
        if (monthlyEnabled)
          PriceInputField(
            controller: monthlyController,
            currency: currency,
            label: 'Monthly Rate',
            hint: 'Price per month',
            helperText: 'Offer a discount for long-term stays',
            onChanged: onMonthlyChanged,
            textInputAction: TextInputAction.done,
          ),
      ],
    );
  }
}
