import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/image_upload_service.dart';
import '../../widgets/modern_banner.dart';

/// Verification status enum matching database
enum VerificationStatus {
  none,
  pending,
  verified,
  rejected,
}

/// Screen for uploading NID documents for owner verification
class NidVerificationScreen extends StatefulWidget {
  const NidVerificationScreen({
    super.key,
    required this.userId,
    this.onVerificationSubmitted,
  });

  final String userId;
  final VoidCallback? onVerificationSubmitted;

  @override
  State<NidVerificationScreen> createState() => _NidVerificationScreenState();
}

class _NidVerificationScreenState extends State<NidVerificationScreen> {
  final _uploadService = ImageUploadService.instance;

  // NID Front
  PlatformFile? _nidFrontFile;
  Uint8List? _nidFrontBytes;
  bool _isUploadingFront = false;
  String? _nidFrontUrl;
  String? _nidFrontError;

  // NID Back
  PlatformFile? _nidBackFile;
  Uint8List? _nidBackBytes;
  bool _isUploadingBack = false;
  String? _nidBackUrl;
  String? _nidBackError;

  bool _isSubmitting = false;

  bool get _canSubmit =>
      _nidFrontUrl != null &&
      _nidBackUrl != null &&
      !_isSubmitting &&
      !_isUploadingFront &&
      !_isUploadingBack;

  Future<void> _pickNidFront() async {
    final file = await _uploadService.pickDocument();
    if (file == null) return;

    Uint8List? bytes;
    if (kIsWeb) {
      bytes = file.bytes;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }

    setState(() {
      _nidFrontFile = file;
      _nidFrontBytes = bytes;
      _nidFrontError = null;
    });

    await _uploadNidFront();
  }

  Future<void> _uploadNidFront() async {
    if (_nidFrontFile == null) return;

    setState(() {
      _isUploadingFront = true;
      _nidFrontError = null;
    });

    final result = await _uploadService.uploadNidFront(
      file: _nidFrontFile!,
      userId: widget.userId,
    );

    setState(() {
      _isUploadingFront = false;
      if (result.success) {
        _nidFrontUrl = result.publicUrl;
      } else {
        _nidFrontError = result.errorMessage;
      }
    });
  }

  Future<void> _pickNidBack() async {
    final file = await _uploadService.pickDocument();
    if (file == null) return;

    Uint8List? bytes;
    if (kIsWeb) {
      bytes = file.bytes;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }

    setState(() {
      _nidBackFile = file;
      _nidBackBytes = bytes;
      _nidBackError = null;
    });

    await _uploadNidBack();
  }

  Future<void> _uploadNidBack() async {
    if (_nidBackFile == null) return;

    setState(() {
      _isUploadingBack = true;
      _nidBackError = null;
    });

    final result = await _uploadService.uploadNidBack(
      file: _nidBackFile!,
      userId: widget.userId,
    );

    setState(() {
      _isUploadingBack = false;
      if (result.success) {
        _nidBackUrl = result.publicUrl;
      } else {
        _nidBackError = result.errorMessage;
      }
    });
  }

  Future<void> _submitVerification() async {
    if (!_canSubmit) return;

    setState(() => _isSubmitting = true);

    try {
      final client = Supabase.instance.client;

      // Insert or update NID front document
      await client.from('owner_documents').upsert({
        'user_id': widget.userId,
        'document_type': DocumentType.nidFront,
        'file_path': _nidFrontUrl,
        'file_name': _nidFrontFile?.name,
        'file_size': _nidFrontFile?.size,
        'mime_type': _getMimeType(_nidFrontFile?.name),
      }, onConflict: 'user_id,document_type');

      // Insert or update NID back document
      await client.from('owner_documents').upsert({
        'user_id': widget.userId,
        'document_type': DocumentType.nidBack,
        'file_path': _nidBackUrl,
        'file_name': _nidBackFile?.name,
        'file_size': _nidBackFile?.size,
        'mime_type': _getMimeType(_nidBackFile?.name),
      }, onConflict: 'user_id,document_type');

      if (mounted) {
        widget.onVerificationSubmitted?.call();
        Navigator.pop(context);
        ModernBanner.showSuccess(context, 'Documents submitted for verification');
      }
    } catch (e) {
      if (mounted) {
        ModernBanner.showError(context, 'Failed to submit: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String? _getMimeType(String? fileName) {
    if (fileName == null) return null;
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'pdf':
        return 'application/pdf';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Identity'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Upload your NID',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'To verify your identity and enable hosting, please upload clear photos of both sides of your National ID card.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),

            // NID Front
            _DocumentUploadCard(
              title: 'NID Front Side',
              description: 'Upload the front of your National ID',
              icon: Icons.credit_card,
              file: _nidFrontFile,
              imageBytes: _nidFrontBytes,
              uploadedUrl: _nidFrontUrl,
              isUploading: _isUploadingFront,
              error: _nidFrontError,
              onPick: _pickNidFront,
              onRetry: _uploadNidFront,
            ),
            const SizedBox(height: 16),

            // NID Back
            _DocumentUploadCard(
              title: 'NID Back Side',
              description: 'Upload the back of your National ID',
              icon: Icons.credit_card,
              file: _nidBackFile,
              imageBytes: _nidBackBytes,
              uploadedUrl: _nidBackUrl,
              isUploading: _isUploadingBack,
              error: _nidBackError,
              onPick: _pickNidBack,
              onRetry: _uploadNidBack,
            ),
            const SizedBox(height: 32),

            // Tips
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Tips for a successful upload',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Make sure the entire card is visible\n'
                      '• Ensure good lighting without glare\n'
                      '• Keep the image in focus\n'
                      '• Supported formats: JPG, PNG, PDF\n'
                      '• Maximum file size: 10MB',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submitVerification : null,
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
                    : const Text('Submit for Verification'),
              ),
            ),
            const SizedBox(height: 16),

            // Privacy note
            Text(
              'Your documents will be securely stored and only used for identity verification. We take your privacy seriously.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Card widget for uploading a single document
class _DocumentUploadCard extends StatelessWidget {
  const _DocumentUploadCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.file,
    required this.imageBytes,
    required this.uploadedUrl,
    required this.isUploading,
    required this.error,
    required this.onPick,
    required this.onRetry,
  });

  final String title;
  final String description;
  final IconData icon;
  final PlatformFile? file;
  final Uint8List? imageBytes;
  final String? uploadedUrl;
  final bool isUploading;
  final String? error;
  final VoidCallback onPick;
  final VoidCallback onRetry;

  bool get _isPdf => file?.extension?.toLowerCase() == 'pdf';
  bool get _hasFile => file != null;
  bool get _isUploaded => uploadedUrl != null;
  bool get _hasError => error != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: isUploading ? null : onPick,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Preview area
            Container(
              height: 160,
              color: theme.colorScheme.surfaceContainerHighest,
              child: _buildPreview(theme),
            ),

            // Info section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(icon, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _hasFile ? file!.name : description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (_isUploaded)
                    Icon(Icons.check_circle, color: Colors.green)
                  else if (_hasError)
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.red),
                      onPressed: onRetry,
                      tooltip: 'Retry upload',
                    )
                  else if (!_hasFile)
                    Icon(Icons.add_photo_alternate,
                        color: theme.colorScheme.primary),
                ],
              ),
            ),

            // Error message
            if (_hasError)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    if (isUploading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_isPdf && _hasFile) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.picture_as_pdf, size: 48, color: Colors.red[400]),
            const SizedBox(height: 8),
            Text(
              file!.name,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    if (imageBytes != null) {
      return Image.memory(
        imageBytes!,
        fit: BoxFit.cover,
      );
    }

    if (uploadedUrl != null) {
      return Image.network(
        uploadedUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(theme),
      );
    }

    return _buildPlaceholder(theme);
  }

  Widget _buildPlaceholder(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to upload',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
