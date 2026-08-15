import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/discount.dart';

/// Status of promo code validation
enum PromoCodeStatus {
  idle,
  validating,
  valid,
  invalid,
  error,
}

/// Result of promo code validation for display
class PromoCodeDisplayResult {
  const PromoCodeDisplayResult({
    required this.status,
    this.discount,
    this.discountAmount,
    this.message,
    this.errorCode,
  });

  final PromoCodeStatus status;
  final Discount? discount;
  final double? discountAmount;
  final String? message;
  final String? errorCode;

  factory PromoCodeDisplayResult.idle() {
    return const PromoCodeDisplayResult(status: PromoCodeStatus.idle);
  }

  factory PromoCodeDisplayResult.validating() {
    return const PromoCodeDisplayResult(status: PromoCodeStatus.validating);
  }

  factory PromoCodeDisplayResult.valid({
    required Discount discount,
    required double discountAmount,
  }) {
    return PromoCodeDisplayResult(
      status: PromoCodeStatus.valid,
      discount: discount,
      discountAmount: discountAmount,
      message: _getSuccessMessage(discount, discountAmount),
    );
  }

  factory PromoCodeDisplayResult.invalid(String message, [String? errorCode]) {
    return PromoCodeDisplayResult(
      status: PromoCodeStatus.invalid,
      message: message,
      errorCode: errorCode,
    );
  }

  factory PromoCodeDisplayResult.error(String message) {
    return PromoCodeDisplayResult(
      status: PromoCodeStatus.error,
      message: message,
    );
  }

  static String _getSuccessMessage(Discount discount, double amount) {
    if (discount.type == DiscountType.percentage) {
      return 'You\'ll save ৳${amount.toStringAsFixed(0)} (${discount.value.toStringAsFixed(0)}% off)';
    } else if (discount.type == DiscountType.freeNights &&
        discount.freeNightsConfig != null) {
      return 'Stay ${discount.freeNightsConfig!.stayNights}, Pay ${discount.freeNightsConfig!.payNights}!';
    }
    return 'You\'ll save ৳${amount.toStringAsFixed(0)}';
  }

  bool get isValid => status == PromoCodeStatus.valid;
  bool get isValidating => status == PromoCodeStatus.validating;
  bool get hasError =>
      status == PromoCodeStatus.invalid || status == PromoCodeStatus.error;
}

/// Callback for promo code validation
typedef PromoCodeValidator = Future<PromoCodeDisplayResult> Function(
    String code);

/// Callback when a valid code is applied
typedef OnPromoCodeApplied = void Function(
    Discount discount, double discountAmount);

/// Promo code input widget with validation
class PromoCodeInput extends StatefulWidget {
  const PromoCodeInput({
    super.key,
    required this.onValidate,
    this.onApplied,
    this.onRemoved,
    this.initialCode,
    this.enabled = true,
    this.autoValidate = false,
    this.showApplyButton = true,
    this.hintText = 'Enter promo code',
    this.labelText,
    this.helperText,
    this.appliedDiscount,
  });

  final PromoCodeValidator onValidate;
  final OnPromoCodeApplied? onApplied;
  final VoidCallback? onRemoved;
  final String? initialCode;
  final bool enabled;
  final bool autoValidate;
  final bool showApplyButton;
  final String hintText;
  final String? labelText;
  final String? helperText;
  final Discount? appliedDiscount;

  @override
  State<PromoCodeInput> createState() => _PromoCodeInputState();
}

class _PromoCodeInputState extends State<PromoCodeInput> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  PromoCodeDisplayResult _result = PromoCodeDisplayResult.idle();
  bool _hasApplied = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCode);
    _hasApplied = widget.appliedDiscount != null;

    if (widget.autoValidate &&
        widget.initialCode != null &&
        widget.initialCode!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _validateCode());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _validateCode() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() {
        _result = PromoCodeDisplayResult.idle();
      });
      return;
    }

    setState(() {
      _result = PromoCodeDisplayResult.validating();
    });

    try {
      final result = await widget.onValidate(code);
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _result = PromoCodeDisplayResult.error('Failed to validate code');
      });
    }
  }

  void _applyCode() {
    if (_result.isValid &&
        _result.discount != null &&
        _result.discountAmount != null) {
      setState(() {
        _hasApplied = true;
      });
      widget.onApplied?.call(_result.discount!, _result.discountAmount!);
    }
  }

  void _removeCode() {
    setState(() {
      _controller.clear();
      _result = PromoCodeDisplayResult.idle();
      _hasApplied = false;
    });
    widget.onRemoved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_hasApplied && (widget.appliedDiscount != null || _result.isValid)) {
      return _buildAppliedView(theme, colorScheme);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled && !_result.isValidating,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  LengthLimitingTextInputFormatter(20),
                ],
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  labelText: widget.labelText,
                  helperText: widget.helperText,
                  prefixIcon: const Icon(Icons.local_offer_outlined),
                  suffixIcon: _buildSuffixIcon(),
                  border: const OutlineInputBorder(),
                  errorText: _result.hasError ? _result.message : null,
                  errorMaxLines: 2,
                ),
                onChanged: (value) {
                  if (_result.status != PromoCodeStatus.idle) {
                    setState(() {
                      _result = PromoCodeDisplayResult.idle();
                    });
                  }
                },
                onSubmitted: (_) => _validateCode(),
              ),
            ),
            if (widget.showApplyButton) ...[
              const SizedBox(width: 12),
              _buildApplyButton(colorScheme),
            ],
          ],
        ),
        if (_result.isValid && !_hasApplied) ...[
          const SizedBox(height: 8),
          _buildValidResult(theme, colorScheme),
        ],
      ],
    );
  }

  Widget? _buildSuffixIcon() {
    if (_result.isValidating) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_result.isValid) {
      return const Icon(Icons.check_circle, color: Colors.green);
    }

    if (_result.hasError) {
      return const Icon(Icons.error, color: Colors.red);
    }

    if (_controller.text.isNotEmpty) {
      return IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          _controller.clear();
          setState(() {
            _result = PromoCodeDisplayResult.idle();
          });
        },
      );
    }

    return null;
  }

  Widget _buildApplyButton(ColorScheme colorScheme) {
    final canApply = _controller.text.trim().isNotEmpty &&
        !_result.isValidating &&
        widget.enabled;

    if (_result.isValid && !_hasApplied) {
      return FilledButton(
        onPressed: _applyCode,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
        child: const Text('Apply'),
      );
    }

    return FilledButton.tonal(
      onPressed: canApply ? _validateCode : null,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      child: _result.isValidating
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Check'),
    );
  }

  Widget _buildValidResult(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _result.discount?.name ?? 'Promo Code',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
                Text(
                  _result.message ?? '',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppliedView(ThemeData theme, ColorScheme colorScheme) {
    final discount = widget.appliedDiscount ?? _result.discount;
    final amount = _result.discountAmount ?? 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.local_offer,
              color: colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      discount?.code ?? _controller.text.toUpperCase(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'APPLIED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  discount?.name ?? 'Promo Code Applied',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                if (amount > 0)
                  Text(
                    'Saving ৳${amount.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.enabled)
            IconButton(
              icon: Icon(
                Icons.close,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: _removeCode,
              tooltip: 'Remove code',
            ),
        ],
      ),
    );
  }
}

/// Compact promo code input for inline use
class CompactPromoCodeInput extends StatefulWidget {
  const CompactPromoCodeInput({
    super.key,
    required this.onValidate,
    this.onApplied,
    this.onRemoved,
    this.appliedDiscount,
  });

  final PromoCodeValidator onValidate;
  final OnPromoCodeApplied? onApplied;
  final VoidCallback? onRemoved;
  final Discount? appliedDiscount;

  @override
  State<CompactPromoCodeInput> createState() => _CompactPromoCodeInputState();
}

class _CompactPromoCodeInputState extends State<CompactPromoCodeInput> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.appliedDiscount != null) {
      return _buildAppliedChip(theme, colorScheme);
    }

    if (!_isExpanded) {
      return TextButton.icon(
        onPressed: () => setState(() => _isExpanded = true),
        icon: const Icon(Icons.local_offer_outlined, size: 18),
        label: const Text('Add promo code'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      );
    }

    return PromoCodeInput(
      onValidate: widget.onValidate,
      onApplied: (discount, amount) {
        widget.onApplied?.call(discount, amount);
        setState(() => _isExpanded = false);
      },
      onRemoved: () {
        widget.onRemoved?.call();
        setState(() => _isExpanded = false);
      },
      showApplyButton: true,
      hintText: 'Promo code',
    );
  }

  Widget _buildAppliedChip(ThemeData theme, ColorScheme colorScheme) {
    return Chip(
      avatar: Icon(
        Icons.local_offer,
        size: 18,
        color: colorScheme.primary,
      ),
      label: Text(
        widget.appliedDiscount?.code ?? 'PROMO',
        style: TextStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: widget.onRemoved,
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
      side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
    );
  }
}
