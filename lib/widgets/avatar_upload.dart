import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/image_upload_service.dart';
import 'modern_banner.dart';

/// Widget for displaying and uploading user avatar
class AvatarUpload extends StatefulWidget {
  const AvatarUpload({
    super.key,
    required this.currentAvatarUrl,
    required this.userName,
    required this.userId,
    required this.onAvatarChanged,
    this.radius = 40,
    this.editable = true,
  });

  final String? currentAvatarUrl;
  final String userName;
  final String userId;
  final ValueChanged<String?> onAvatarChanged;
  final double radius;
  final bool editable;

  @override
  State<AvatarUpload> createState() => _AvatarUploadState();
}

class _AvatarUploadState extends State<AvatarUpload> {
  final _uploadService = ImageUploadService.instance;

  bool _isUploading = false;
  double _uploadProgress = 0;
  String? _localImagePath;
  Uint8List? _localImageBytes;

  Future<void> _pickAndUploadAvatar() async {
    if (!widget.editable || _isUploading) return;

    final source = await _showImageSourceDialog();
    if (source == null) return;

    XFile? file;
    if (source == ImageSource.camera) {
      file = await _uploadService.pickImageFromCamera();
    } else {
      file = await _uploadService.pickImageFromGallery();
    }

    if (file == null) return;

    // Show local preview immediately
    final bytes = await file.readAsBytes();
    setState(() {
      _localImagePath = file!.path;
      _localImageBytes = bytes;
      _isUploading = true;
      _uploadProgress = 0;
    });

    // Upload to Supabase
    final result = await _uploadService.uploadAvatar(
      image: file,
      userId: widget.userId,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _uploadProgress = progress);
        }
      },
    );

    if (mounted) {
      setState(() => _isUploading = false);

      if (result.success && result.publicUrl != null) {
        widget.onAvatarChanged(result.publicUrl);
        ModernBanner.showSuccess(context, 'Avatar updated successfully');
      } else {
        // Clear local preview on error
        setState(() {
          _localImagePath = null;
          _localImageBytes = null;
        });
        ModernBanner.showError(context, result.errorMessage ?? 'Failed to upload avatar');
      }
    }
  }

  Future<ImageSource?> _showImageSourceDialog() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            if (widget.currentAvatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove photo',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _removeAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text('Your profile photo will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _uploadService.deleteAvatar(widget.userId);
      widget.onAvatarChanged(null);
      setState(() {
        _localImagePath = null;
        _localImageBytes = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: widget.editable ? _pickAndUploadAvatar : null,
      child: Stack(
        children: [
          // Avatar image
          CircleAvatar(
            radius: widget.radius,
            backgroundImage: _getImageProvider(),
            child: _getImageProvider() == null
                ? Text(
                    widget.userName.isNotEmpty
                        ? widget.userName[0].toUpperCase()
                        : 'U',
                    style: theme.textTheme.headlineMedium,
                  )
                : null,
          ),

          // Upload progress overlay
          if (_isUploading)
            Positioned.fill(
              child: CircleAvatar(
                radius: widget.radius,
                backgroundColor: Colors.black45,
                child: SizedBox(
                  width: widget.radius,
                  height: widget.radius,
                  child: CircularProgressIndicator(
                    value: _uploadProgress > 0 ? _uploadProgress : null,
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
              ),
            ),

          // Edit badge
          if (widget.editable && !_isUploading)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.camera_alt,
                  size: widget.radius * 0.35,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  ImageProvider? _getImageProvider() {
    // Prefer local preview during upload
    if (_localImageBytes != null) {
      return MemoryImage(_localImageBytes!);
    }
    if (_localImagePath != null && !kIsWeb) {
      return FileImage(File(_localImagePath!));
    }
    if (widget.currentAvatarUrl != null) {
      return NetworkImage(widget.currentAvatarUrl!);
    }
    return null;
  }
}
