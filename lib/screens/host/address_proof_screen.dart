import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/responsive.dart';
import '../../models/address_verification.dart';
import '../../services/image_upload_service.dart';
import '../../widgets/modern_banner.dart';

/// Collects the two halves of a host's address submission before they can add
/// a listing: a billed copy (utility bill, etc.) and the full address in
/// writing. Pops `true` once both are in.
///
/// Submitting is all that publishing waits for. The "Address verified" badge
/// comes later, when a Musafir admin has physically visited the address and
/// approved it — days, not seconds — so this screen is careful to promise a
/// visit rather than an instant tick.
class AddressProofScreen extends StatefulWidget {
  const AddressProofScreen({super.key, required this.userId});

  final String userId;

  @override
  State<AddressProofScreen> createState() => _AddressProofScreenState();
}

class _AddressProofScreenState extends State<AddressProofScreen> {
  final TextEditingController _address = TextEditingController();

  XFile? _doc;
  Uint8List? _preview;
  bool _isUploading = false;

  /// Where this host already stands. Drives the banner at the top and lets a
  /// rejected host see the reason and edit what they last typed instead of
  /// starting over.
  AddressVerification _existing = AddressVerification.none;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final existing =
        await ImageUploadService.instance.addressVerification(widget.userId);
    if (!mounted) return;
    setState(() {
      _existing = existing;
      _address.text = existing.addressLine ?? '';
      _loading = false;
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
    // A document already on file counts, so a rejected host fixing only their
    // address doesn't have to photograph the same bill again.
    if (_doc == null && !_existing.hasProofDocument) {
      ModernBanner.showError(context, 'Please add a proof-of-address document');
      return;
    }
    if (_address.text.trim().isEmpty) {
      ModernBanner.showError(context, 'Please enter your full address');
      return;
    }

    setState(() => _isUploading = true);

    if (_doc != null) {
      final result = await ImageUploadService.instance.uploadAddressProof(
        image: _doc!,
        userId: widget.userId,
      );
      if (!mounted) return;
      if (!result.success) {
        setState(() => _isUploading = false);
        ModernBanner.showError(
          context,
          result.errorMessage ?? 'Upload failed. Please try again.',
        );
        return;
      }
    }

    // Only now does the submission exist: the server refuses an address with no
    // document behind it, so the upload has to land first.
    final error = await ImageUploadService.instance.submitAddressVerification(
      addressLine: _address.text,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    if (error != null) {
      ModernBanner.showError(context, error);
      return;
    }
    Navigator.pop(context, true);
  }

  /// The standing verdict, when there is one. A pending host is told a visit is
  /// coming so silence doesn't read as a lost submission; a rejected one is
  /// told exactly what to fix.
  Widget? _statusBanner(ThemeData theme) {
    final (IconData icon, Color color, String title, String? body) =
        switch (_existing.status) {
      AddressVerificationStatus.pending => (
          Icons.schedule_rounded,
          AppColors.amber,
          'Visit pending',
          'A Musafir admin will visit this address to verify it. You can '
              'publish listings in the meantime — the verified badge appears '
              'once the visit is done.',
        ),
      AddressVerificationStatus.verified => (
          Icons.verified_rounded,
          AppColors.success,
          'Address verified',
          'An admin has visited and confirmed this address.',
        ),
      AddressVerificationStatus.rejected => (
          Icons.error_outline_rounded,
          theme.colorScheme.error,
          'Address could not be verified',
          _existing.reason,
        ),
      AddressVerificationStatus.none => (
          Icons.abc,
          Colors.transparent,
          '',
          null
        ),
    };
    if (_existing.status == AddressVerificationStatus.none) return null;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (body != null && body.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDoc = _preview != null;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Verify your address')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final banner = _statusBanner(theme);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your address')),
      body: ResponsiveCenter(
        maxWidth: 640,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (banner != null) banner,
                Text(
                  'Verify your address',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Upload a recent bill showing your name and address, and tell us '
                  'the full address. A Musafir admin then visits in person to '
                  'verify it. Submitting is all you need to publish a listing — '
                  'the verified badge appears after the visit.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),

                Text(
                  'Billed copy',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'A gas, electricity or water bill, bank statement, or similar.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),

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
                if (!hasDoc && _existing.hasProofDocument) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 15, color: AppColors.success),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'A document is already on file. Tap above only to '
                          'replace it.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),

                Text(
                  'Full address',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Everything an admin needs to find the door: house and road '
                  'number, flat or floor, area, city and postcode.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _address,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 300,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.streetAddress,
                  decoration: const InputDecoration(
                    hintText:
                        'e.g. Flat 4B, House 42, Road 7, Block C, Banani, '
                        'Dhaka 1213',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),

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
                      : Text(_existing.isRejected
                          ? 'Resubmit & continue'
                          : 'Submit & continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
