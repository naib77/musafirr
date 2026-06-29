import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../services/image_upload_service.dart';
import '../../services/nid/bypass_nid_verification.dart';
import '../../state/auth_state.dart';
import '../../state/otp_state.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/modern_banner.dart';
import '../../widgets/nid_input_field.dart';

/// An identity document the guest can choose to upload for verification.
class _IdDocType {
  const _IdDocType(
    this.key,
    this.label,
    this.icon, {
    this.requiresNumber = false,
  });

  final String key;
  final String label;
  final IconData icon;

  /// Whether a typed document number is collected (only National ID for now).
  final bool requiresNumber;
}

const List<_IdDocType> _idDocTypes = [
  _IdDocType('nid', 'National ID (NID)', Icons.credit_card_rounded,
      requiresNumber: true),
  _IdDocType('passport', 'Passport', Icons.flight_takeoff_rounded),
  _IdDocType('driving_license', 'Driving License',
      Icons.directions_car_filled_rounded),
  _IdDocType('student_id', 'Student / Admission', Icons.school_rounded),
  _IdDocType('office_id', 'Office / Employee ID', Icons.badge_rounded),
];

/// Screen for completing profile after phone verification
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
  final _nidController = TextEditingController();
  final _dobController = TextEditingController();

  bool _isLoading = false;
  DateTime? _selectedDob;

  // Chosen identity document + its captured images. Front is mandatory, back is
  // optional. Bytes are cached for preview so thumbnails render the same on
  // mobile and web.
  String _selectedTypeKey = 'nid';
  XFile? _idFront;
  Uint8List? _idFrontPreview;
  XFile? _idBack;
  Uint8List? _idBackPreview;

  _IdDocType get _currentType =>
      _idDocTypes.firstWhere((t) => t.key == _selectedTypeKey);

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _nidController.dispose();
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

  /// Switching document type clears any captured images so the two slots always
  /// belong to the same document.
  void _selectType(String key) {
    if (key == _selectedTypeKey) return;
    setState(() {
      _selectedTypeKey = key;
      _idFront = null;
      _idFrontPreview = null;
      _idBack = null;
      _idBackPreview = null;
    });
  }

  /// Ask the user to capture a document side from camera or pick from gallery.
  Future<ImageSource?> _pickSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureSide({required bool isFront}) async {
    final source = await _pickSource();
    if (source == null) return;

    final service = ImageUploadService.instance;
    final XFile? image = source == ImageSource.camera
        ? await service.pickImageFromCamera()
        : await service.pickImageFromGallery();
    if (image == null) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      if (isFront) {
        _idFront = image;
        _idFrontPreview = bytes;
      } else {
        _idBack = image;
        _idBackPreview = bytes;
      }
    });
  }

  Future<void> _handleCompleteRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedDob == null) {
      ModernBanner.showError(context, 'Please select your date of birth');
      return;
    }

    // Front is mandatory for every document; back is optional.
    if (_idFront == null) {
      ModernBanner.showError(
        context,
        'Please scan the front of your ${_currentType.label}',
      );
      return;
    }

    setState(() => _isLoading = true);

    // The typed number + verification only apply to the National ID.
    String nidNumber = '';
    if (_currentType.requiresNumber) {
      nidNumber = _nidController.text.trim();
      final nidService = NidVerificationFactory.getService();
      final nidResult = await nidService.verifyNid(
        nidNumber: nidNumber,
        dateOfBirth: _dobController.text,
      );
      if (!nidResult.success) {
        if (mounted) {
          setState(() => _isLoading = false);
          ModernBanner.showError(
              context, nidResult.errorMessage ?? 'NID verification failed');
        }
        return;
      }
    }

    // Create user via auth state.
    final success = await widget.authState.signupWithPhone(
      phone: widget.otpState.phoneNumber!,
      name: _nameController.text.trim(),
      nid: nidNumber,
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

    // The auth user now exists and is signed in, so RLS lets us upload the
    // document scans (storage + owner_documents both require auth.uid()).
    await _uploadIdentityImages();

    if (mounted) {
      setState(() => _isLoading = false);
      widget.otpState.completeProfile();
    }
  }

  /// Uploads the chosen document to the private `documents` store and records
  /// its type. Best-effort: the account is already created, so an upload hiccup
  /// warns rather than blocks — the user can re-upload later from their profile.
  Future<void> _uploadIdentityImages() async {
    final userId = widget.authState.currentUser?.id;
    if (userId == null) return;

    final service = ImageUploadService.instance;
    await service.setIdDocumentType(userId: userId, idType: _selectedTypeKey);

    final front = await service.uploadIdentityImage(
      image: _idFront!,
      userId: userId,
      idType: _selectedTypeKey,
      isFront: true,
    );

    UploadResult? back;
    if (_idBack != null) {
      back = await service.uploadIdentityImage(
        image: _idBack!,
        userId: userId,
        idType: _selectedTypeKey,
        isFront: false,
      );
    }

    if (mounted && (!front.success || (back != null && !back.success))) {
      ModernBanner.showWarning(
        context,
        'Your account is ready, but your document images didn\'t fully '
        'upload. You can re-upload them later from your profile.',
      );
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Welcome message
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
                const SizedBox(height: 24),

                // Identity document type selector
                Row(
                  children: [
                    Text(
                      'Verify your identity',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '*',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Choose a document and photograph it. Required to build trust '
                  'in our community.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final type in _idDocTypes)
                      ChoiceChip(
                        selected: type.key == _selectedTypeKey,
                        onSelected: (_) => _selectType(type.key),
                        avatar: Icon(
                          type.icon,
                          size: 18,
                          color: type.key == _selectedTypeKey
                              ? Colors.white
                              : AppColors.brand,
                        ),
                        label: Text(type.label),
                        selectedColor: AppColors.brand,
                        labelStyle: TextStyle(
                          color: type.key == _selectedTypeKey
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Document number — National ID only.
                if (_currentType.requiresNumber) ...[
                  NidInputField(
                    controller: _nidController,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 16),
                ],

                // Capture cards: front (required) + back (optional)
                Text(
                  'Scan your ${_currentType.label}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DocCaptureCard(
                        label: 'Front side',
                        preview: _idFrontPreview,
                        onTap: () => _captureSide(isFront: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DocCaptureCard(
                        label: 'Back side',
                        optional: true,
                        preview: _idBackPreview,
                        onTap: () => _captureSide(isFront: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Info box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Your document is stored securely and used only for '
                          'identity verification.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Complete Registration button
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
    );
  }
}

/// A tap-to-scan card for one side of an identity document. Shows a placeholder
/// until captured, then the photo with an edit affordance and a check badge.
class _DocCaptureCard extends StatelessWidget {
  const _DocCaptureCard({
    required this.label,
    required this.preview,
    required this.onTap,
    this.optional = false,
  });

  final String label;
  final Uint8List? preview;
  final VoidCallback onTap;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final captured = preview != null;

    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1.5,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  captured ? AppColors.brand : theme.colorScheme.outlineVariant,
              width: captured ? 2 : 1,
            ),
          ),
          child: captured
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(preview!, fit: BoxFit.cover),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black54,
                        child: const Icon(Icons.edit,
                            size: 14, color: Colors.white),
                      ),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_rounded,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 3),
                            Text(
                              label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_a_photo_outlined,
                      size: 26,
                      color: AppColors.brand,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      optional ? 'Optional' : 'Tap to scan',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
