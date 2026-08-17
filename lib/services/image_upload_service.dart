import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'image_compression_service.dart';

/// Storage bucket names
class StorageBuckets {
  static const String listingImages = 'listing-images';
  static const String avatars = 'avatars';
  static const String documents = 'documents';
  static const String chatAttachments = 'chat-attachments';
}

/// Document types for owner verification
class DocumentType {
  static const String nidFront = 'nid_front';
  static const String nidBack = 'nid_back';
  static const String selfie = 'selfie';
}

/// Result of a file upload operation
class UploadResult {
  final bool success;
  final String? publicUrl;
  final String? storagePath;
  final String? errorMessage;

  const UploadResult._({
    required this.success,
    this.publicUrl,
    this.storagePath,
    this.errorMessage,
  });

  factory UploadResult.success({
    required String publicUrl,
    required String storagePath,
  }) {
    return UploadResult._(
      success: true,
      publicUrl: publicUrl,
      storagePath: storagePath,
    );
  }

  factory UploadResult.failure(String message) {
    return UploadResult._(
      success: false,
      errorMessage: message,
    );
  }
}

/// Progress callback for uploads
typedef UploadProgressCallback = void Function(double progress);

/// Service for handling image and file uploads to Supabase Storage
class ImageUploadService {
  ImageUploadService._();

  static ImageUploadService? _instance;
  static ImageUploadService get instance {
    _instance ??= ImageUploadService._();
    return _instance!;
  }

  final ImagePicker _imagePicker = ImagePicker();
  SupabaseClient get _client => Supabase.instance.client;
  SupabaseStorageClient get _storage => _client.storage;

  /// Configuration
  static const int maxListingImages = 10;
  static const int maxImageWidth = 1920;
  static const int imageQuality = 85;

  // ============== Image Picking ==============

  /// Pick a single image from gallery
  Future<XFile?> pickImageFromGallery() async {
    try {
      return await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxImageWidth.toDouble(),
        imageQuality: imageQuality,
      );
    } catch (e) {
      debugPrint('[ImageUploadService] Error picking image from gallery: $e');
      return null;
    }
  }

  /// Pick a single image from camera
  Future<XFile?> pickImageFromCamera() async {
    try {
      return await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxImageWidth.toDouble(),
        imageQuality: imageQuality,
      );
    } catch (e) {
      debugPrint('[ImageUploadService] Error picking image from camera: $e');
      return null;
    }
  }

  /// Take a selfie with the front-facing camera. Used for identity
  /// verification, where a live face photo (not a gallery pick) is required.
  Future<XFile?> pickSelfieFromCamera() async {
    try {
      return await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: maxImageWidth.toDouble(),
        imageQuality: imageQuality,
      );
    } catch (e) {
      debugPrint('[ImageUploadService] Error taking selfie: $e');
      return null;
    }
  }

  /// Pick multiple images from gallery
  Future<List<XFile>> pickMultipleImages({int? limit}) async {
    try {
      final images = await _imagePicker.pickMultiImage(
        maxWidth: maxImageWidth.toDouble(),
        imageQuality: imageQuality,
        limit: limit,
      );
      return images;
    } catch (e) {
      debugPrint('[ImageUploadService] Error picking multiple images: $e');
      return [];
    }
  }

  /// Pick a file (for documents - supports PDF)
  Future<PlatformFile?> pickFile({
    List<String>? allowedExtensions,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: allowedExtensions != null ? FileType.custom : FileType.any,
        allowedExtensions: allowedExtensions,
        withData: kIsWeb, // Load bytes for web
      );
      return result?.files.firstOrNull;
    } catch (e) {
      debugPrint('[ImageUploadService] Error picking file: $e');
      return null;
    }
  }

  /// Pick an image or PDF for documents
  Future<PlatformFile?> pickDocument() async {
    return pickFile(allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf']);
  }

  // ============== Upload to Supabase ==============

  /// Upload an XFile to a bucket.
  ///
  /// When [compressionProfile] is provided the image is re-encoded/resized
  /// before upload (see [ImageCompressionService]); the stored file's extension
  /// is rewritten to match the resulting format. Pass null for files that must
  /// keep full fidelity (e.g. verification documents).
  Future<UploadResult> uploadXFile({
    required XFile file,
    required String bucket,
    required String path,
    ImageCompressionProfile? compressionProfile,
    UploadProgressCallback? onProgress,
  }) async {
    try {
      var bytes = await file.readAsBytes();

      // Try multiple sources for MIME type (web often has blob URLs without extensions)
      var mimeType = file.mimeType ??
          lookupMimeType(file.path) ??
          lookupMimeType(file.name) ??
          _detectMimeTypeFromBytes(bytes) ??
          'image/jpeg'; // Safe default for image uploads

      debugPrint(
          '[ImageUploadService] Detected MIME type: $mimeType for ${file.name}');

      var uploadPath = path;
      if (compressionProfile != null) {
        final before = bytes.length;
        final compressed = await ImageCompressionService.instance.compress(
          bytes,
          profile: compressionProfile,
          sourceMime: mimeType,
        );
        bytes = compressed.bytes;
        mimeType = compressed.mimeType;
        // Keep the stored extension consistent with the actual bytes.
        uploadPath = _pathWithExtensionForMime(path, mimeType);
        debugPrint(
            '[ImageUploadService] Compressed ${(before / 1024).round()}KB -> ${(bytes.length / 1024).round()}KB ($mimeType)');
      }

      return await _uploadBytes(
        bytes: bytes,
        bucket: bucket,
        path: uploadPath,
        mimeType: mimeType,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('[ImageUploadService] Error uploading XFile: $e');
      return UploadResult.failure('Failed to read file: $e');
    }
  }

  /// Replaces the extension of [path] with the canonical one for [mimeType]
  /// (so a JPEG re-encoded to WebP is stored as `.webp`).
  String _pathWithExtensionForMime(String path, String mimeType) {
    final ext = switch (mimeType) {
      'image/webp' => 'webp',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      _ => null,
    };
    if (ext == null) return path;
    final dir = p.dirname(path);
    final base = p.basenameWithoutExtension(path);
    final newName = '$base.$ext';
    return dir == '.' ? newName : '$dir/$newName';
  }

  /// Detect MIME type from file bytes (magic numbers)
  String? _detectMimeTypeFromBytes(Uint8List bytes) {
    if (bytes.length < 4) return null;

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }

    // WebP: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }

    // PDF: %PDF
    if (bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }

    return null;
  }

  /// Upload a PlatformFile to a bucket
  Future<UploadResult> uploadPlatformFile({
    required PlatformFile file,
    required String bucket,
    required String path,
    UploadProgressCallback? onProgress,
  }) async {
    try {
      Uint8List bytes;

      if (kIsWeb) {
        if (file.bytes == null) {
          return UploadResult.failure('File bytes not available on web');
        }
        bytes = file.bytes!;
      } else {
        if (file.path == null) {
          return UploadResult.failure('File path not available');
        }
        bytes = await File(file.path!).readAsBytes();
      }

      final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';

      return await _uploadBytes(
        bytes: bytes,
        bucket: bucket,
        path: path,
        mimeType: mimeType,
        onProgress: onProgress,
      );
    } catch (e) {
      debugPrint('[ImageUploadService] Error uploading PlatformFile: $e');
      return UploadResult.failure('Failed to read file: $e');
    }
  }

  /// Core upload method using bytes
  Future<UploadResult> _uploadBytes({
    required Uint8List bytes,
    required String bucket,
    required String path,
    required String mimeType,
    UploadProgressCallback? onProgress,
  }) async {
    try {
      debugPrint('[ImageUploadService] Uploading to $bucket/$path ($mimeType)');

      // Upload to Supabase Storage
      await _storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: true, // Overwrite if exists
            ),
          );

      // Get public URL
      final publicUrl = _storage.from(bucket).getPublicUrl(path);

      debugPrint('[ImageUploadService] Upload successful: $publicUrl');

      return UploadResult.success(
        publicUrl: publicUrl,
        storagePath: path,
      );
    } on StorageException catch (e) {
      debugPrint('[ImageUploadService] Storage error: ${e.message}');
      return UploadResult.failure(e.message);
    } catch (e) {
      debugPrint('[ImageUploadService] Upload error: $e');
      return UploadResult.failure('Upload failed: $e');
    }
  }

  // ============== Listing Images ==============

  /// Upload a listing image
  Future<UploadResult> uploadListingImage({
    required XFile image,
    required String listingId,
    UploadProgressCallback? onProgress,
  }) async {
    final ext = p.extension(image.path).toLowerCase().replaceAll('.', '');
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${_generateId()}.$ext';
    final path = '$listingId/$fileName';

    return uploadXFile(
      file: image,
      bucket: StorageBuckets.listingImages,
      path: path,
      compressionProfile: ImageCompressionProfile.listing,
      onProgress: onProgress,
    );
  }

  /// Upload multiple listing images
  Future<List<UploadResult>> uploadListingImages({
    required List<XFile> images,
    required String listingId,
    void Function(int current, int total, double progress)? onProgress,
  }) async {
    final results = <UploadResult>[];

    for (var i = 0; i < images.length; i++) {
      final result = await uploadListingImage(
        image: images[i],
        listingId: listingId,
        onProgress: (progress) {
          onProgress?.call(i + 1, images.length, progress);
        },
      );
      results.add(result);
    }

    return results;
  }

  /// Delete a listing image
  Future<bool> deleteListingImage(String storagePath) async {
    return _deleteFile(StorageBuckets.listingImages, storagePath);
  }

  // ============== Avatar ==============

  /// Upload user avatar
  Future<UploadResult> uploadAvatar({
    required XFile image,
    required String userId,
    UploadProgressCallback? onProgress,
  }) async {
    final ext = p.extension(image.path).toLowerCase().replaceAll('.', '');
    final path = '$userId.$ext';

    return uploadXFile(
      file: image,
      bucket: StorageBuckets.avatars,
      path: path,
      compressionProfile: ImageCompressionProfile.avatar,
      onProgress: onProgress,
    );
  }

  /// Delete user avatar
  Future<bool> deleteAvatar(String userId) async {
    // Try common extensions (webp is now the compressed default).
    for (final ext in ['webp', 'jpg', 'jpeg', 'png']) {
      final deleted = await _deleteFile(StorageBuckets.avatars, '$userId.$ext');
      if (deleted) return true;
    }
    return false;
  }

  // ============== Documents ==============

  /// Upload a verification document (NID front/back)
  Future<UploadResult> uploadDocument({
    required PlatformFile file,
    required String userId,
    required String documentType,
    UploadProgressCallback? onProgress,
  }) async {
    final ext = p.extension(file.name).toLowerCase().replaceAll('.', '');
    final fileName =
        '${documentType}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = '$userId/$fileName';

    return uploadPlatformFile(
      file: file,
      bucket: StorageBuckets.documents,
      path: path,
      onProgress: onProgress,
    );
  }

  /// Upload NID front image
  Future<UploadResult> uploadNidFront({
    required PlatformFile file,
    required String userId,
    UploadProgressCallback? onProgress,
  }) async {
    return uploadDocument(
      file: file,
      userId: userId,
      documentType: DocumentType.nidFront,
      onProgress: onProgress,
    );
  }

  /// Upload NID back image
  Future<UploadResult> uploadNidBack({
    required PlatformFile file,
    required String userId,
    UploadProgressCallback? onProgress,
  }) async {
    return uploadDocument(
      file: file,
      userId: userId,
      documentType: DocumentType.nidBack,
      onProgress: onProgress,
    );
  }

  /// Upload one side of an identity document captured as an [XFile]
  /// (camera/gallery) to the private `documents` bucket, then record it in
  /// `owner_documents` so it's linked to the user and enters verification.
  ///
  /// [idType] is the human-meaningful document the user chose
  /// ('nid' | 'passport' | 'driving_license' | 'student_id' | 'office_id'); it
  /// is encoded in the storage path and stored on `profiles.id_document_type`
  /// (see [setIdDocumentType]). The two `owner_documents` slots stay
  /// `nid_front` / `nid_back` regardless of [idType], because that table's CHECK
  /// constraint and verification trigger are keyed to those two slot names.
  ///
  /// Must be called while authenticated (storage + table RLS require auth.uid()).
  Future<UploadResult> uploadIdentityImage({
    required XFile image,
    required String userId,
    required String idType,
    required bool isFront,
    UploadProgressCallback? onProgress,
  }) async {
    final ext = p.extension(image.name).toLowerCase().replaceAll('.', '');
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final side = isFront ? 'front' : 'back';
    final path =
        '$userId/${idType}_${side}_${DateTime.now().millisecondsSinceEpoch}.$safeExt';

    final result = await uploadXFile(
      file: image,
      bucket: StorageBuckets.documents,
      path: path,
      onProgress: onProgress,
    );

    if (!result.success) return result;

    // Best-effort: link the stored file to the user. The image is already
    // safely in storage even if this row write fails.
    final slot = isFront ? DocumentType.nidFront : DocumentType.nidBack;
    try {
      await _client.from('owner_documents').upsert(
        {
          'user_id': userId,
          'document_type': slot,
          'file_path': result.storagePath,
          'file_name': image.name,
          'mime_type':
              image.mimeType ?? lookupMimeType(image.path) ?? 'image/jpeg',
        },
        onConflict: 'user_id,document_type',
      );
    } catch (e) {
      debugPrint('[ImageUploadService] owner_documents record failed: $e');
    }

    return result;
  }

  /// Upload the identity-verification selfie (front camera) to the private
  /// `documents` bucket and record it in `owner_documents` under the `selfie`
  /// slot, so it sits alongside the ID document for admin review.
  Future<UploadResult> uploadSelfieImage({
    required XFile image,
    required String userId,
    UploadProgressCallback? onProgress,
  }) async {
    final ext = p.extension(image.name).toLowerCase().replaceAll('.', '');
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final path =
        '$userId/selfie_${DateTime.now().millisecondsSinceEpoch}.$safeExt';

    final result = await uploadXFile(
      file: image,
      bucket: StorageBuckets.documents,
      path: path,
      onProgress: onProgress,
    );

    if (!result.success) return result;

    try {
      await _client.from('owner_documents').upsert(
        {
          'user_id': userId,
          'document_type': DocumentType.selfie,
          'file_path': result.storagePath,
          'file_name': image.name,
          'mime_type':
              image.mimeType ?? lookupMimeType(image.path) ?? 'image/jpeg',
        },
        onConflict: 'user_id,document_type',
      );
    } catch (e) {
      debugPrint(
          '[ImageUploadService] owner_documents (selfie) record failed: $e');
    }

    return result;
  }

  /// Moves the user into the admin review queue by setting their
  /// `verification_status` to `pending`. Called once all documents (ID + selfie)
  /// have been submitted. Idempotent.
  Future<void> markVerificationPending(String userId) async {
    try {
      await _client
          .from('profiles')
          .update({'verification_status': 'pending'}).eq('id', userId);
    } catch (e) {
      debugPrint('[ImageUploadService] markVerificationPending failed: $e');
    }
  }

  /// The user's identity verification status: `none` | `pending` | `verified` |
  /// `rejected`. Falls back to `none` on any error.
  Future<String> identityVerificationStatus(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('verification_status')
          .eq('id', userId)
          .maybeSingle();
      return (row?['verification_status'] as String?) ?? 'none';
    } catch (e) {
      debugPrint('[ImageUploadService] identityVerificationStatus failed: $e');
      return 'none';
    }
  }

  /// The most recent rejection reason on any of the user's documents, if the
  /// verification was rejected. Null when none is recorded.
  Future<String?> latestRejectionReason(String userId) async {
    try {
      final rows = await _client
          .from('owner_documents')
          .select('rejection_reason')
          .eq('user_id', userId)
          .not('rejection_reason', 'is', null)
          .order('uploaded_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty) {
        return rows.first['rejection_reason'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('[ImageUploadService] latestRejectionReason failed: $e');
      return null;
    }
  }

  /// A short-lived signed URL for a private `documents` file (used by admin
  /// review to preview documents the bucket won't serve publicly).
  Future<String?> signedDocumentUrl(String filePath,
      {int expiresIn = 3600}) async {
    try {
      return await _storage
          .from(StorageBuckets.documents)
          .createSignedUrl(filePath, expiresIn);
    } catch (e) {
      debugPrint('[ImageUploadService] signedDocumentUrl failed: $e');
      return null;
    }
  }

  /// Records which identity document the user chose and its number on their
  /// profile ([idType] → `id_document_type`, [idNumber] → `nid`). Best-effort:
  /// signup still succeeds (and images still upload) even if this write fails.
  Future<void> setIdDocumentType({
    required String userId,
    required String idType,
    String? idNumber,
  }) async {
    try {
      final data = <String, dynamic>{'id_document_type': idType};
      if (idNumber != null && idNumber.isNotEmpty) {
        data['nid'] = idNumber;
      }
      await _client.from('profiles').update(data).eq('id', userId);
    } catch (e) {
      debugPrint('[ImageUploadService] setIdDocumentType failed: $e');
    }
  }

  // ============== Proof of address (host) ==============

  /// Uploads a host's proof-of-address document (utility bill, etc.) to the
  /// private `documents` bucket and stores its path on the profile. Presence of
  /// that path is what unlocks listing creation when the requirement is on.
  Future<UploadResult> uploadAddressProof({
    required XFile image,
    required String userId,
    UploadProgressCallback? onProgress,
  }) async {
    final ext = p.extension(image.name).toLowerCase().replaceAll('.', '');
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final path =
        '$userId/address_proof_${DateTime.now().millisecondsSinceEpoch}.$safeExt';

    final result = await uploadXFile(
      file: image,
      bucket: StorageBuckets.documents,
      path: path,
      onProgress: onProgress,
    );

    if (!result.success) return result;

    try {
      await _client
          .from('profiles')
          .update({'address_proof_path': result.storagePath}).eq('id', userId);
    } catch (e) {
      debugPrint('[ImageUploadService] address_proof_path update failed: $e');
    }

    return result;
  }

  /// Whether the user has a proof-of-address document on file.
  Future<bool> hasAddressProof(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('address_proof_path')
          .eq('id', userId)
          .maybeSingle();
      final path = row?['address_proof_path'] as String?;
      return path != null && path.isNotEmpty;
    } catch (e) {
      debugPrint('[ImageUploadService] hasAddressProof failed: $e');
      return false;
    }
  }

  // ============== Identity verification (guest + host) ==============

  /// Whether the user has any identity document on file. Presence of a row in
  /// `owner_documents` is what unlocks the gated actions (adding a listing,
  /// booking) — upload is enough, no admin approval required.
  Future<bool> hasIdentityDocument(String userId) async {
    try {
      final row = await _client
          .from('owner_documents')
          .select('user_id')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
      return row != null;
    } catch (e) {
      debugPrint('[ImageUploadService] hasIdentityDocument failed: $e');
      return false;
    }
  }

  // ============== Helpers ==============

  /// Delete a file from storage
  Future<bool> _deleteFile(String bucket, String path) async {
    try {
      await _storage.from(bucket).remove([path]);
      debugPrint('[ImageUploadService] Deleted: $bucket/$path');
      return true;
    } catch (e) {
      debugPrint('[ImageUploadService] Delete error: $e');
      return false;
    }
  }

  /// Generate a random ID for file names
  String _generateId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().microsecondsSinceEpoch;
    return List.generate(8, (i) => chars[(random + i * 7) % chars.length])
        .join();
  }

  /// Get optimized URL with size parameters
  String getOptimizedUrl(
    String url, {
    int? width,
    int? height,
    int quality = 80,
  }) {
    // Supabase Storage transform parameters
    final params = <String>[];
    if (width != null) params.add('width=$width');
    if (height != null) params.add('height=$height');
    params.add('quality=$quality');

    if (params.isEmpty) return url;

    final separator = url.contains('?') ? '&' : '?';
    return '$url$separator${params.join('&')}';
  }

  /// Get thumbnail URL (300px width)
  String getThumbnailUrl(String url) {
    return getOptimizedUrl(url, width: 300, quality: 70);
  }

  /// Get medium URL (600px width)
  String getMediumUrl(String url) {
    return getOptimizedUrl(url, width: 600, quality: 80);
  }
}
