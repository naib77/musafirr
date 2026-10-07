import 'package:flutter/material.dart';

import '../services/booking/hourly_policy.dart'
    show formatClockMinutes, parseClockMinutes;
import '../services/clock_label.dart';
import 'app_text_field.dart';

/// A time field with a clock: the host can type, or tap the dial and pick an
/// hour and minute on a 12-hour AM/PM face (any minute — no snapping).
///
/// Typing is kept alongside the picker on purpose (2026-10-07; Jev was
/// unsure, 0.43, so this was Claude's call): a desktop host filling in
/// twenty room types is faster on the keyboard, the existing text defaults
/// and tests keep working, and the hourly window's `24:00` has no spelling a
/// 12-hour dial can produce.
///
/// [use24h] decides what the picker *writes*, not what it shows — the dial
/// is always AM/PM, which is how the request was phrased and how hosts here
/// read a clock:
///  * false (check-in / check-out): a label like `2:30 PM`, the free-text
///    form `check_in_time` has always held ([formatClockLabel]).
///  * true (hourly window): `HH:MM` for the `time` columns (148).
class ClockTextField extends StatelessWidget {
  const ClockTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.onChanged,
    this.use24h = false,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool use24h;
  final String? Function(String?)? validator;

  Future<void> _pick(BuildContext context) async {
    // Open on what the field says when it parses, so the host adjusts rather
    // than re-enters; 2 PM is the forms' long-standing default.
    final current = use24h
        ? parseClockMinutes(controller.text)
        : parseClockLabelMinutes(controller.text);
    final picked = await showTimePicker(
      context: context,
      initialTime: timeOfDayFromMinutes(current ?? 14 * 60),
      initialEntryMode: TimePickerEntryMode.dial,
      helpText: label.toUpperCase(),
      builder: (context, child) => MediaQuery(
        // The dial reads AM/PM whatever the device's clock setting is.
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: child!,
      ),
    );
    if (picked == null) return;
    final minutes = minutesFromTimeOfDay(picked);
    controller.text =
        use24h ? formatClockMinutes(minutes) : formatClockLabel(minutes);
    onChanged?.call(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      hint: hint,
      keyboardType: TextInputType.datetime,
      onChanged: onChanged,
      // These fields are optional everywhere they appear; AppTextField's
      // default validator would make them required.
      validator: validator ?? (_) => null,
      // A Tooltip does not name a control for assistive tech; Semantics does
      // (edge-functions-and-accessibility.md).
      suffix: Semantics(
        button: true,
        label: 'Pick $label',
        child: IconButton(
          icon: const Icon(Icons.schedule),
          tooltip: 'Pick a time',
          onPressed: () => _pick(context),
        ),
      ),
    );
  }
}
