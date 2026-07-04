import 'package:flutter/material.dart';

import '../../core/currency/currency.dart';
import '../../widgets/app_text_field.dart';

/// Validates the three plan rates for a listing. Returns a user-facing message,
/// or null if valid. Shared by the create and edit listing flows.
///
/// Rules:
/// - at least one plan must be enabled,
/// - each enabled plan needs a positive rate,
/// - rates must strictly increase by duration (hourly < daily < monthly)
///   across the enabled plans.
String? validatePlanRates({
  required bool hourlyEnabled,
  required bool dailyEnabled,
  required bool monthlyEnabled,
  required String hourlyText,
  required String dailyText,
  required String monthlyText,
}) {
  final hourly = hourlyEnabled ? double.tryParse(hourlyText) : null;
  final daily = dailyEnabled ? double.tryParse(dailyText) : null;
  final monthly = monthlyEnabled ? double.tryParse(monthlyText) : null;

  if (!hourlyEnabled && !dailyEnabled && !monthlyEnabled) {
    return 'Enable at least one pricing plan.';
  }
  if (hourlyEnabled && (hourly == null || hourly <= 0)) {
    return 'Enter a valid hourly rate.';
  }
  if (dailyEnabled && (daily == null || daily <= 0)) {
    return 'Enter a valid daily rate.';
  }
  if (monthlyEnabled && (monthly == null || monthly <= 0)) {
    return 'Enter a valid monthly rate.';
  }

  // Enforce hourly < daily < monthly across the enabled plans (unit order).
  final ordered = [
    if (hourly != null) hourly,
    if (daily != null) daily,
    if (monthly != null) monthly,
  ];
  for (var i = 0; i < ordered.length - 1; i++) {
    if (ordered[i] >= ordered[i + 1]) {
      return 'Rates must increase by duration: hourly < daily < monthly.';
    }
  }
  return null;
}

/// A single per-plan pricing row: an enable toggle plus a rate field that greys
/// out and ignores input when the plan is off. Shared by create and edit.
class PlanPriceRow extends StatelessWidget {
  const PlanPriceRow({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.hint,
    required this.helperText,
    required this.enabled,
    required this.onToggled,
    required this.onChanged,
    this.minController,
    this.maxController,
    this.unitLabel,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String hint;
  final String helperText;
  final bool enabled;
  final ValueChanged<bool> onToggled;
  final VoidCallback onChanged;

  /// When provided, shows Min / Max booking-duration fields for this plan.
  /// [unitLabel] is the duration unit (e.g. 'hours', 'nights', 'months').
  final TextEditingController? minController;
  final TextEditingController? maxController;
  final String? unitLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: enabled ? theme.colorScheme.primary : mutedColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: enabled ? null : mutedColor,
                ),
              ),
            ),
            Switch(value: enabled, onChanged: onToggled),
          ],
        ),
        const SizedBox(height: 8),
        Opacity(
          opacity: enabled ? 1.0 : 0.4,
          child: IgnorePointer(
            ignoring: !enabled,
            child: AppTextField(
              controller: controller,
              label: '',
              hint: hint,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              prefix: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(Currency.BDT.symbol),
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          enabled ? helperText : 'Not offered',
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
        if (minController != null && maxController != null) ...[
          const SizedBox(height: 12),
          Opacity(
            opacity: enabled ? 1.0 : 0.4,
            child: IgnorePointer(
              ignoring: !enabled,
              child: Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: minController!,
                      label: 'Min ${unitLabel ?? ''}'.trim(),
                      hint: '1',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                      controller: maxController!,
                      label: 'Max ${unitLabel ?? ''}'.trim(),
                      hint: 'No limit',
                      keyboardType: TextInputType.number,
                      onChanged: (_) => onChanged(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
