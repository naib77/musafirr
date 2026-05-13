import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// NID input field with validation for Bangladesh National ID
class NidInputField extends StatelessWidget {
  const NidInputField({
    super.key,
    required this.controller,
    this.label = 'National ID Number',
    this.hint = 'Enter your 10 or 17 digit NID',
    this.validator,
    this.onFieldSubmitted,
    this.textInputAction = TextInputAction.done,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final TextInputAction textInputAction;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Validate Bangladesh NID number
  /// Old NID: 10 digits
  /// New NID: 17 digits
  static String? validateBdNid(String? value) {
    if (value == null || value.isEmpty) {
      return 'NID number is required';
    }

    // Remove any spaces
    final cleaned = value.replaceAll(RegExp(r'\s'), '');

    // Must be all digits
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
      return 'NID must contain only numbers';
    }

    // Check length: 10 (old) or 17 (new)
    if (cleaned.length != 10 && cleaned.length != 17) {
      return 'NID must be 10 digits (old) or 17 digits (new)';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      enabled: enabled,
      autofocus: autofocus,
      focusNode: focusNode,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(17),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.credit_card),
        helperText: 'Old NID: 10 digits, New NID: 17 digits',
      ),
      validator: validator ?? validateBdNid,
    );
  }
}
