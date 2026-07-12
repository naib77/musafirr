import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/image_upload_service.dart';
import 'modern_banner.dart';

/// A selected image that may or may not be uploaded yet
class SelectedImage {
  final String? localPath; // For local files (mobile)
  final Uint8List? bytes; // For web or preview
  final String? uploadedUrl; // After upload to storage
  final String? storagePath; // Storage path for deletion
  final bool isUploading;
  final double uploadProgress;
  final String? error;

  const SelectedImage({
    this.localPath,
    this.bytes,
    this.uploadedUrl,
    this.storagePath,
    this.isUploading = false,
    this.uploadProgress = 0,
    this.error,
  });

  bool get isUploaded => uploadedUrl != null;
  bool get hasError => error != null;

  SelectedImage copyWith({
    String? localPath,
    Uint8List? bytes,
    String? uploadedUrl,
    String? storagePath,
    bool? isUploading,
    double? uploadProgress,
    String? error,
  }) {
    return SelectedImage(
      localPath: localPath ?? this.localPath,
      bytes: bytes ?? this.bytes,
      uploadedUrl: uploadedUrl ?? this.uploadedUrl,
      storagePath: storagePath ?? this.storagePath,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      error: error,
    );
  }
}

/// Grid widget for selecting and managing multiple images
class ImagePickerGrid extends StatefulWidget {
  const ImagePickerGrid({
    super.key,
    required this.images,
    required this.onImagesChanged,
    this.maxImages = 10,
    this.crossAxisCount = 3,
    this.aspectRatio = 1.0,
    this.showAddButton = true,
    this.enabled = true,
  });

  final List<SelectedImage> images;
  final ValueChanged<List<SelectedImage>> onImagesChanged;
  final int maxImages;
  final int crossAxisCount;
  final double aspectRatio;
  final bool showAddButton;
  final bool enabled;

  @override
  State<ImagePickerGrid> createState() => _ImagePickerGridState();
}

class _ImagePickerGridState extends State<ImagePickerGrid> {
  final _uploadService = ImageUploadService.instance;

  Future<void> _pickImages() async {
    if (!widget.enabled) return;

    final remaining = widget.maxImages - widget.images.length;
    if (remaining <= 0) {
      _showMaxImagesError();
      return;
    }

    final source = await _showImageSourceDialog();
    if (source == null) return;

    List<XFile> files = [];

    if (source == ImageSource.camera) {
      final file = await _uploadService.pickImageFromCamera();
      if (file != null) files = [file];
    } else {
      files = await _uploadService.pickMultipleImages(limit: remaining);
    }

    if (files.isEmpty) return;

    // Convert to SelectedImage objects
    final newImages = <SelectedImage>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      newImages.add(SelectedImage(
        localPath: file.path,
        bytes: bytes,
      ));
    }

    widget.onImagesChanged([...widget.images, ...newImages]);
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
          ],
        ),
      ),
    );
  }

  void _showMaxImagesError() {
    ModernBanner.showWarning(context, 'Maximum ${widget.maxImages} images allowed');
  }

  Future<void> _removeImage(int index) async {
    if (index < 0 || index >= widget.images.length) return;
    final isCover = index == 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove photo?'),
        content: Text(
          isCover
              ? 'This is your cover photo. Removing it will make the next '
                  'photo the cover.'
              : 'This photo will be removed from your listing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final newImages = [...widget.images];
    newImages.removeAt(index);
    widget.onImagesChanged(newImages);
  }

  void _reorderImages(int oldIndex, int newIndex) {
    if (!widget.enabled) return;

    final newImages = [...widget.images];
    if (newIndex > oldIndex) newIndex--;
    final item = newImages.removeAt(oldIndex);
    newImages.insert(newIndex, item);
    widget.onImagesChanged(newImages);
  }

  /// Promotes the image at [index] to the front so it becomes the cover.
  /// The cover is always the first photo, and the parent screens persist
  /// `image_urls` in this list's order, so moving it to index 0 is all that's
  /// needed for it to save as the cover.
  Future<void> _setCover(int index) async {
    if (!widget.enabled || index <= 0 || index >= widget.images.length) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set as cover?'),
        content: const Text(
          'This photo will become the cover — the first image guests see for '
          'your listing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Set cover'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final newImages = [...widget.images];
    final item = newImages.removeAt(index);
    newImages.insert(0, item);
    widget.onImagesChanged(newImages);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAddMore = widget.images.length < widget.maxImages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with count
        Row(
          children: [
            Text(
              'Photos',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${widget.images.length}/${widget.maxImages}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Help text
        Text(
          'The first photo is the cover. Tap the star on any photo to make '
          'it the cover.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),

        // Image grid
        ReorderableWrap(
          spacing: 8,
          runSpacing: 8,
          onReorder: _reorderImages,
          children: [
            // Existing images
            ...widget.images.asMap().entries.map((entry) {
              final index = entry.key;
              final image = entry.value;
              return _ImageTile(
                key: ValueKey('image_$index'),
                image: image,
                index: index,
                isFirst: index == 0,
                onRemove: widget.enabled ? () => _removeImage(index) : null,
                onSetCover: widget.enabled ? () => _setCover(index) : null,
                size: _calculateTileSize(context),
              );
            }),

            // Add button
            if (widget.showAddButton && canAddMore && widget.enabled)
              _AddImageTile(
                key: const ValueKey('add_button'),
                onTap: _pickImages,
                size: _calculateTileSize(context),
              ),
          ],
        ),
      ],
    );
  }

  double _calculateTileSize(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final padding = 24.0 * 2; // Screen padding
    final spacing = 8.0 * (widget.crossAxisCount - 1);
    return (screenWidth - padding - spacing) / widget.crossAxisCount;
  }
}

/// Individual image tile
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    super.key,
    required this.image,
    required this.index,
    required this.isFirst,
    required this.onRemove,
    required this.onSetCover,
    required this.size,
  });

  final SelectedImage image;
  final int index;
  final bool isFirst;
  final VoidCallback? onRemove;
  final VoidCallback? onSetCover;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _buildImage(),
          ),

          // Cover badge on the first photo; a tappable "Set cover" chip on the
          // rest (hidden while uploading / on error).
          if (isFirst)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded,
                        size: 12, color: theme.colorScheme.onPrimary),
                    const SizedBox(width: 3),
                    Text(
                      'Cover',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (onSetCover != null && !image.isUploading && !image.hasError)
            Positioned(
              bottom: 4,
              left: 4,
              child: GestureDetector(
                onTap: onSetCover,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_border_rounded,
                          size: 12, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'Set cover',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Upload progress overlay
          if (image.isUploading)
            Container(
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: CircularProgressIndicator(
                  value: image.uploadProgress > 0 ? image.uploadProgress : null,
                  color: Colors.white,
                ),
              ),
            ),

          // Error overlay
          if (image.hasError)
            Container(
              decoration: BoxDecoration(
                color: Colors.red.withAlpha(128),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.error, color: Colors.white),
              ),
            ),

          // Remove button
          if (onRemove != null && !image.isUploading)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    if (image.bytes != null) {
      return Image.memory(
        image.bytes!,
        fit: BoxFit.cover,
      );
    } else if (image.localPath != null && !kIsWeb) {
      return Image.file(
        File(image.localPath!),
        fit: BoxFit.cover,
      );
    } else if (image.uploadedUrl != null) {
      return Image.network(
        image.uploadedUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image),
        ),
      );
    }
    return const Center(child: Icon(Icons.image));
  }
}

/// Add image button tile
class _AddImageTile extends StatelessWidget {
  const _AddImageTile({
    super.key,
    required this.onTap,
    required this.size,
  });

  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate,
                size: 32,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 4),
              Text(
                'Add',
                style: theme.textTheme.labelSmall?.copyWith(
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

/// Simple reorderable wrap widget
class ReorderableWrap extends StatelessWidget {
  const ReorderableWrap({
    super.key,
    required this.children,
    required this.onReorder,
    this.spacing = 0,
    this.runSpacing = 0,
  });

  final List<Widget> children;
  final void Function(int oldIndex, int newIndex) onReorder;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    // Simple wrap without drag-to-reorder for now
    // Full reorder would need a more complex implementation
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: children,
    );
  }
}
