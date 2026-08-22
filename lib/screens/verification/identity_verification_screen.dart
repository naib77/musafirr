import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/modern_banner.dart';
import 'selfie_capture_screen.dart';

/// An identity document the user can upload for verification.
class _IdDocType {
  const _IdDocType(this.key, this.label, this.icon, this.numberLabel);

  final String key;
  final String label;
  final IconData icon;

  /// Label for the ID-number field on step 1, e.g. "NID number".
  final String numberLabel;
}

const List<_IdDocType> _idDocTypes = [
  _IdDocType(
      'nid', 'National ID (NID)', Icons.credit_card_rounded, 'NID number'),
  _IdDocType(
      'passport', 'Passport', Icons.flight_takeoff_rounded, 'Passport number'),
  _IdDocType('driving_license', 'Driving License',
      Icons.directions_car_filled_rounded, 'License number'),
  _IdDocType('student_id', 'Student / Admission', Icons.school_rounded,
      'Student / Admission ID'),
  _IdDocType(
      'office_id', 'Office / Employee ID', Icons.badge_rounded, 'Employee ID'),
];

/// Standalone screen that captures and uploads an identity document. Used both
/// as the one-time gate before hosting/booking and from the profile screen.
/// The caller must already be authenticated (storage + `owner_documents` RLS
/// require `auth.uid()`). Pops `true` once the front image has uploaded.
class IdentityVerificationScreen extends StatefulWidget {
  const IdentityVerificationScreen({
    super.key,
    required this.userId,
    this.reason,
  });

  final String userId;

  /// Short phrase completing "Verify your identity ...", e.g.
  /// "to publish a listing". When null a generic subtitle is shown.
  final String? reason;

  @override
  State<IdentityVerificationScreen> createState() =>
      _IdentityVerificationScreenState();
}

class _IdentityVerificationScreenState
    extends State<IdentityVerificationScreen> {
  // Two-step wizard: 0 = document type + number, 1 = selfie + document scans.
  // Bytes are cached so previews render the same on mobile and web.
  int _step = 0;
  String _selectedTypeKey = 'nid';
  final _idNumberController = TextEditingController();
  final _detailsFormKey = GlobalKey<FormState>();
  XFile? _idFront;
  Uint8List? _idFrontPreview;
  XFile? _idBack;
  Uint8List? _idBackPreview;
  XFile? _selfie;
  Uint8List? _selfiePreview;
  bool _isSubmitting = false;

  // Current server-side verification status, loaded on open. While it's loading
  // we show a spinner; if it's already 'pending' or 'verified' we show that
  // state instead of the form so a returning user can't re-submit mid-review.
  bool _loadingStatus = true;
  String _status = 'none';

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await ImageUploadService.instance
        .identityVerificationStatus(widget.userId);
    if (!mounted) return;
    setState(() {
      _status = status;
      _loadingStatus = false;
    });
  }

  _IdDocType get _currentType =>
      _idDocTypes.firstWhere((t) => t.key == _selectedTypeKey);

  /// NID must have both sides scanned; for every other document the back is
  /// optional.
  bool get _backRequired => _selectedTypeKey == 'nid';

  /// Validates the ID number field. A Bangladesh NID is exactly 10 or 17
  /// digits; other document numbers only need to be non-empty.
  String? _validateIdNumber(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Please enter your ${_currentType.numberLabel}';
    if (_selectedTypeKey == 'nid') {
      final digits = v.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 10 && digits.length != 17) {
        return 'A Bangladesh NID number is 10 or 17 digits';
      }
    }
    return null;
  }

  @override
  void dispose() {
    _idNumberController.dispose();
    super.dispose();
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

  /// Selfie is taken with the front camera only (no gallery) — it must be a
  /// live face photo for verification.
  ///
  /// Uses the in-app [SelfieCaptureScreen], which selects the front lens
  /// itself. Handing off to the system camera app does NOT work: the
  /// `preferredCameraDevice` hint is advisory and many Android camera apps —
  /// and mobile browsers that delegate to them — ignore it and open the rear
  /// camera. Falls back to the picker only when the device reports no front
  /// camera at all, so a guest is never dead-ended.
  Future<void> _captureSelfie() async {
    final captured = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(builder: (_) => const SelfieCaptureScreen()),
    );
    if (!mounted) return;

    XFile? image;
    if (captured is XFile) {
      image = captured;
    } else if (captured == SelfieCaptureResult.unavailable) {
      // No front lens. The picker's hint is the best remaining option, and the
      // guest is told why the camera may not face them.
      ModernBanner.showInfo(
        context,
        'No front camera found — please make sure your face is in the photo.',
      );
      image = await ImageUploadService.instance.pickSelfieFromCamera();
    }
    if (image == null) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _selfie = image;
      _selfiePreview = bytes;
    });
  }

  /// Advances from step 1 (type + number) to step 2 (selfie + scans) once the
  /// ID number is filled in.
  void _goToDocuments() {
    if (_detailsFormKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    setState(() => _step = 1);
  }

  Future<void> _submit() async {
    // Selfie first, then the ID document — matching the on-screen order.
    if (_selfie == null) {
      ModernBanner.showError(
        context,
        'Please take a selfie so we can match it to your document',
      );
      return;
    }
    if (_idFront == null) {
      ModernBanner.showError(
        context,
        'Please scan the front of your ${_currentType.label}',
      );
      return;
    }
    if (_backRequired && _idBack == null) {
      ModernBanner.showError(
        context,
        'Please scan the back of your ${_currentType.label} too',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final service = ImageUploadService.instance;
    await service.setIdDocumentType(
      userId: widget.userId,
      idType: _selectedTypeKey,
      idNumber: _idNumberController.text.trim(),
    );

    final selfie = await service.uploadSelfieImage(
      image: _selfie!,
      userId: widget.userId,
    );

    final front = await service.uploadIdentityImage(
      image: _idFront!,
      userId: widget.userId,
      idType: _selectedTypeKey,
      isFront: true,
    );

    UploadResult? back;
    if (_idBack != null) {
      back = await service.uploadIdentityImage(
        image: _idBack!,
        userId: widget.userId,
        idType: _selectedTypeKey,
        isFront: false,
      );
    }

    // Required uploads: selfie, front, and — for NID — the back too.
    final backFailedRequired = _backRequired && (back == null || !back.success);
    if (!selfie.success || !front.success || backFailedRequired) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ModernBanner.showError(
        context,
        (!selfie.success
                ? selfie.errorMessage
                : !front.success
                    ? front.errorMessage
                    : back?.errorMessage) ??
            "Couldn't upload your documents. Please try again.",
      );
      return;
    }

    // Everything required landed — enter the admin review queue.
    await service.markVerificationPending(widget.userId);

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!_backRequired && back != null && !back.success) {
      ModernBanner.showWarning(
        context,
        'Submitted. The back side didn\'t upload — you can add it later '
        'from your profile.',
      );
    } else {
      ModernBanner.showSuccess(
        context,
        'Submitted for review — an admin will approve your identity shortly',
      );
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loadingStatus) {
      return const Scaffold(
        body: ResponsiveCenter(
          maxWidth: 640,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    // Already submitted (pending) or approved (verified): show that state
    // rather than the submission form — a returning user waits for the admin.
    if (_status == 'pending' || _status == 'verified') {
      return _buildStatusView(theme);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0 ? 'Verify identity' : 'Selfie & document'),
        // On step 2, the back arrow returns to step 1 rather than leaving the
        // flow, so captured details aren't lost.
        leading: _step == 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed:
                    _isSubmitting ? null : () => setState(() => _step = 0),
              )
            : null,
      ),
      body: ResponsiveCenter(
        maxWidth: 640,
        child: SafeArea(
          child: _step == 0
              ? _buildDetailsStep(theme)
              : _buildDocumentsStep(theme),
        ),
      ),
    );
  }

  /// Shown when the user has already submitted (pending) or been approved
  /// (verified). Replaces the form so they can't re-submit while under review.
  Widget _buildStatusView(ThemeData theme) {
    final verified = _status == 'verified';
    final accent = verified ? AppColors.success : AppColors.warning;
    return Scaffold(
      appBar: AppBar(title: const Text('Identity verification')),
      body: ResponsiveCenter(
        maxWidth: 640,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      verified
                          ? Icons.verified_rounded
                          : Icons.hourglass_top_rounded,
                      size: 44,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    verified ? 'Identity verified' : 'Under review',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    verified
                        ? "Your identity has been approved. You're all set to host and book."
                        : "You've submitted your identity documents. An admin will "
                            "review and approve them shortly — you'll be able to host "
                            'and book once approved.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Got it'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Step 1 — choose the document type and enter its number.
  Widget _buildDetailsStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _detailsFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Verify your identity',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              widget.reason != null
                  ? 'A one-time step ${widget.reason}. Step 1 of 2 — choose your '
                      'document and enter its number.'
                  : 'Step 1 of 2 — choose your document and enter its number.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            Text(
              'Document type',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
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
            const SizedBox(height: 24),
            TextFormField(
              controller: _idNumberController,
              textInputAction: TextInputAction.done,
              keyboardType: _selectedTypeKey == 'nid'
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: _currentType.numberLabel,
                hintText: _selectedTypeKey == 'nid'
                    ? 'Enter your 10- or 17-digit NID number'
                    : 'Enter your ${_currentType.numberLabel}',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.tag_rounded),
              ),
              validator: _validateIdNumber,
              onFieldSubmitted: (_) => _goToDocuments(),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _goToDocuments,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }

  /// Step 2 — take a selfie, then scan the document.
  Widget _buildDocumentsStep(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Selfie & document',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Step 2 of 2 — take a selfie, then scan your ${_currentType.label}.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),

          // 1. Selfie first — a live front-camera photo, matched to the
          // document by the admin reviewer.
          Text(
            '1. Take a selfie',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'A clear photo of your face, so we can match it to your document.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _DocCaptureCard(
            label: 'Selfie',
            icon: Icons.face_retouching_natural_rounded,
            preview: _selfiePreview,
            onTap: _captureSelfie,
          ),
          const SizedBox(height: 24),

          // 2. Document scan.
          Text(
            '2. Scan your ${_currentType.label}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            _backRequired
                ? 'Both the front and back are required.'
                : 'The front is required; the back is optional.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  optional: !_backRequired,
                  preview: _idBackPreview,
                  onTap: () => _captureSide(isFront: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

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

          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Submit'),
          ),
        ],
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
    this.icon = Icons.add_a_photo_outlined,
  });

  final String label;
  final Uint8List? preview;
  final VoidCallback onTap;
  final bool optional;
  final IconData icon;

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
                      icon,
                      size: 26,
                      color: AppColors.brand,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
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
