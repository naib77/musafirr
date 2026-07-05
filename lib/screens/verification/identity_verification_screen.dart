import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/modern_banner.dart';

/// An identity document the user can upload for verification.
class _IdDocType {
  const _IdDocType(this.key, this.label, this.icon);

  final String key;
  final String label;
  final IconData icon;
}

const List<_IdDocType> _idDocTypes = [
  _IdDocType('nid', 'National ID (NID)', Icons.credit_card_rounded),
  _IdDocType('passport', 'Passport', Icons.flight_takeoff_rounded),
  _IdDocType('driving_license', 'Driving License',
      Icons.directions_car_filled_rounded),
  _IdDocType('student_id', 'Student / Admission', Icons.school_rounded),
  _IdDocType('office_id', 'Office / Employee ID', Icons.badge_rounded),
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
  // Chosen document + captured images. Front is mandatory, back optional.
  // Bytes are cached so previews render the same on mobile and web.
  String _selectedTypeKey = 'nid';
  XFile? _idFront;
  Uint8List? _idFrontPreview;
  XFile? _idBack;
  Uint8List? _idBackPreview;
  bool _isSubmitting = false;

  _IdDocType get _currentType =>
      _idDocTypes.firstWhere((t) => t.key == _selectedTypeKey);

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

  Future<void> _submit() async {
    if (_idFront == null) {
      ModernBanner.showError(
        context,
        'Please scan the front of your ${_currentType.label}',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final service = ImageUploadService.instance;
    await service.setIdDocumentType(
      userId: widget.userId,
      idType: _selectedTypeKey,
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

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    // The front image must land for the upload to count. A failed (optional)
    // back is a soft warning, not a blocker.
    if (!front.success) {
      ModernBanner.showError(
        context,
        front.errorMessage ?? "Couldn't upload your document. Please try again.",
      );
      return;
    }

    if (back != null && !back.success) {
      ModernBanner.showWarning(
        context,
        'Front uploaded. The back side didn\'t upload — you can add it later '
        'from your profile.',
      );
    }
    ModernBanner.showSuccess(context, 'Identity document uploaded');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify identity')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
                    ? 'A one-time step ${widget.reason}. Choose a document and '
                        'photograph it — you won\'t be asked again.'
                    : 'Choose a document and photograph it to build trust in '
                        'our community.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),

              // Document type selector
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
              const SizedBox(height: 20),

              Text(
                'Scan your ${_currentType.label}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
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
