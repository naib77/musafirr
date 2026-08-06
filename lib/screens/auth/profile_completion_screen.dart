import 'package:flutter/material.dart';

import '../../core/utils/responsive.dart';
import '../../state/auth_state.dart';
import '../../state/otp_state.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/modern_banner.dart';

/// Screen for completing profile after phone verification. Collects only the
/// basics needed to create an account — name, optional email, and date of
/// birth. Identity verification is no longer required here; it is a one-time
/// gate that fires the first time the user hosts or books.
class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({
    super.key,
    required this.otpState,
    required this.authState,
  });

  final OtpStateNotifier otpState;
  final AuthStateNotifier authState;

  @override
  State<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();

  bool _isLoading = false;
  DateTime? _selectedDob;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    super.dispose();
  }

  Future<void> _selectDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - 18), // Must be at least 18
      helpText: 'Select your date of birth',
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobController.text =
            '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
      });
    }
  }

  Future<void> _handleCompleteRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDob == null) {
      ModernBanner.showError(context, 'Please select your date of birth');
      return;
    }

    setState(() => _isLoading = true);

    final success = await widget.authState.signupWithPhone(
      phone: widget.otpState.phoneNumber!,
      name: _nameController.text.trim(),
      nid: '',
      email: _emailController.text.trim().isNotEmpty
          ? _emailController.text.trim()
          : null,
    );

    if (!success) {
      if (mounted) {
        setState(() => _isLoading = false);
        ModernBanner.showError(
            context, widget.authState.error ?? 'Registration failed');
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoading = false);
      widget.otpState.completeProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Profile'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ResponsiveCenter(
          maxWidth: Responsive.formMaxWidth,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Almost there!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please complete your profile to continue.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                // Full Name (required)
                AppTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'Enter your full name',
                  keyboardType: TextInputType.name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  prefix: const Icon(Icons.person_outline),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Full name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email (optional)
                AppTextField(
                  controller: _emailController,
                  label: 'Email (Optional)',
                  hint: 'Enter your email address',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  prefix: const Icon(Icons.email_outlined),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return null; // Optional field
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Date of Birth (required)
                AppTextField(
                  controller: _dobController,
                  label: 'Date of Birth',
                  hint: 'Select your date of birth',
                  readOnly: true,
                  onTap: _selectDateOfBirth,
                  prefix: const Icon(Icons.calendar_today_outlined),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Date of birth is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                FilledButton(
                  onPressed: _isLoading ? null : _handleCompleteRegistration,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Complete Registration'),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}
