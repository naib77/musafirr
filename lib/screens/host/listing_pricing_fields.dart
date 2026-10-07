import 'package:flutter/material.dart';

import '../../core/currency/currency.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/clock_text_field.dart';

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
    this.extra,
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

  /// Plan-specific fields rendered under the min/max row, greyed out and
  /// inert with the rest of the plan when it is off.
  final Widget? extra;

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
                child: Text(Currency.bdt.symbol),
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
        if (extra != null) ...[
          const SizedBox(height: 12),
          Opacity(
            opacity: enabled ? 1.0 : 0.4,
            child: IgnorePointer(ignoring: !enabled, child: extra),
          ),
        ],
      ],
    );
  }
}

/// The hourly plan's shape beyond price and min/max: which block lengths are
/// sold (blank = any whole number of hours the platform allows) and the
/// day-use window a stay must sit inside (blank = any time). Both are
/// optional narrowings of the platform's `hourly_policy`; a host cannot widen
/// it from here, and the server re-checks whatever is saved.
class HourlyScheduleFields extends StatelessWidget {
  const HourlyScheduleFields({
    super.key,
    required this.slotsController,
    required this.windowStartController,
    required this.windowEndController,
    required this.onChanged,
  });

  final TextEditingController slotsController;
  final TextEditingController windowStartController;
  final TextEditingController windowEndController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: slotsController,
          label: 'Offered durations (hours)',
          hint: 'Any — or e.g. 6, 12',
          keyboardType: TextInputType.text,
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 4),
        Text(
          'Leave empty to let guests pick any number of hours. List a few '
          'to sell fixed blocks only, like a 6-hour day-use.',
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            // 24h here because the stored column is `time` and the existing
            // parser/tests speak HH:MM; the dial is a convenience, typing is
            // kept because 24:00 (midnight end) has no dial spelling.
            Expanded(
              child: ClockTextField(
                controller: windowStartController,
                label: 'Hourly from',
                hint: '09:00',
                use24h: true,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ClockTextField(
                controller: windowEndController,
                label: 'Hourly until',
                hint: '21:00',
                use24h: true,
                onChanged: (_) => onChanged(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Optional. Hourly stays must start and end inside this window. '
          'It may run past midnight, like 22:00 to 02:00 (pick on the '
          'clock, or type 24:00 for midnight).',
          style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
        ),
      ],
    );
  }
}
