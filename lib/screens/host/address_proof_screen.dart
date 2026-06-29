import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/modern_banner.dart';

/// Collects a host's proof-of-address document (utility bill, etc.) before they
/// can add a listing. Pops `true` once the document is uploaded.
class AddressProofScreen extends StatefulWidget {
  const AddressProofScreen({super.key, required this.userId});

  final String userId;

  @override
  State<AddressProofScreen> createState() => _AddressProofScreenState();
}

class _AddressProofScreenState extends State<AddressProofScreen> {
  XFile? _doc;
  Uint8List? _preview;
  bool _isUploading = false;

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

  Future<void> _capture() async {
    final source = await _pickSource();
    if (source == null) return;

    final service = ImageUploadService.instance;
    final image = source == ImageSource.camera
        ? await service.pickImageFromCamera()
        : await service.pickImageFromGallery();
    if (image == null) return;

    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _doc = image;
      _preview = bytes;
    });
  }

  Future<void> _submit() async {
    if (_doc == null) {
      ModernBanner.showError(context, 'Please add a proof-of-address document');
      return;
    }

    setState(() => _isUploading = true);
    final result = await ImageUploadService.instance.uploadAddressProof(
      image: _doc!,
      userId: widget.userId,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (result.success) {
      Navigator.pop(context, true);
    } else {
      ModernBanner.showError(
        context,
        result.errorMessage ?? 'Upload failed. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDoc = _preview != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your address')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add a proof of address',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload a recent document showing your name and address — a gas, '
                'electricity or water bill, bank statement, or similar. Required '
                'before you can publish a listing.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Capture / preview card
              GestureDetector(
                onTap: _capture,
                child: AspectRatio(
                  aspectRatio: 1.4,
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasDoc
                            ? AppColors.brand
                            : theme.colorScheme.outlineVariant,
                        width: hasDoc ? 2 : 1,
                      ),
                    ),
                    child: hasDoc
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(_preview!, fit: BoxFit.cover),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.black54,
                                  child: const Icon(Icons.edit,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined,
                                  size: 32, color: AppColors.brand),
                              const SizedBox(height: 10),
                              Text(
                                'Tap to add document',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Photo or scan',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              FilledButton(
                onPressed: _isUploading ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isUploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Submit & continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
