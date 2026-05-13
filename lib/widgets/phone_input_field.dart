import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Phone input field with Bangladesh flag and +880 prefix
class PhoneInputField extends StatelessWidget {
  const PhoneInputField({
    super.key,
    required this.controller,
    this.label = 'Phone Number',
    this.hint = '1XXXXXXXXX',
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

  /// Validate Bangladesh phone number
  static String? validateBdPhone(String? value) {
    if (value == null || value.isEmpty) {
      return 'Phone number is required';
    }

    // Remove any formatting
    final cleaned = value.replaceAll(RegExp(r'[\s\-]'), '');

    // Check for valid BD number format
    // Can be: 01XXXXXXXXX (11 digits) or 8801XXXXXXXXX (13 digits)
    if (cleaned.length == 11 && cleaned.startsWith('01')) {
      return null;
    }
    if (cleaned.length == 13 && cleaned.startsWith('8801')) {
      return null;
    }
    if (cleaned.length == 10 && cleaned.startsWith('1')) {
      return null; // Without leading 0
    }

    return 'Enter a valid Bangladesh phone number';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      enabled: enabled,
      autofocus: autofocus,
      focusNode: focusNode,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        prefixIcon: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bangladesh flag emoji
              const Text('🇧🇩', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                '+880',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
      validator: validator ?? validateBdPhone,
    );
  }
}
