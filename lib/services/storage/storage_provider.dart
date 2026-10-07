import 'package:flutter/foundation.dart';

/// The transport under every uploaded file: put bytes, name them, sign them,
/// remove them.
///
/// Stage 1 of `docs/plans/aws-s3-storage-migration.md`. Implementations:
/// [SupabaseStorageProvider] (legacy, kept through coexistence and rollback),
/// `S3StorageProvider` (the storage-signer) and `RoutingStorageProvider`,
/// which picks between them per bucket. Callers get one through
/// `defaultStorageProvider()` and never learn which one served them.
///
/// Buckets and paths here are the *logical* names the app already uses
/// (`listing-images`, `{listingId}/{file}`). A future provider maps them to
/// physical locations; callers never learn a physical bucket, key or account.
abstract class StorageProvider {
  /// Stores [bytes] at [bucket]/[path].
  ///
  /// With [upsert] false an existing object is a [StorageConflict], not an
  /// overwrite: face evidence relies on that to make a retried submit find
  /// the already-uploaded immutable capture instead of replacing it.
  ///
  /// Returns the durable URL to store for the object when the provider minted
  /// one (S3 media URLs carry a generation, so a replaced avatar busts caches),
  /// or null when [publicUrl] is the answer, as it always was for Supabase.
  Future<String?> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required bool upsert,
  });

  /// The durable public URL stored in rows such as `listings.image_urls`.
  /// Only meaningful for publicly readable buckets; computing it performs no
  /// request and does not prove the object exists.
  String publicUrl(String bucket, String path);

  /// A short-lived read URL for a private object. Never store the result: a
  /// signed URL is a credential with an expiry, not an identifier.
  Future<String> signedUrl(
    String bucket,
    String path, {
    required int expiresIn,
  });

  /// Removes [paths] from [bucket]. Removing a path that does not exist is
  /// not an error — Supabase answers that with an empty list, and callers
  /// (avatar cleanup tries several extensions) depend on it staying quiet.
  Future<void> remove(String bucket, List<String> paths);
}

/// Any storage failure, provider-neutral. [message] is what the provider said
/// and is what `UploadResult.failure` has always carried.
class StorageFailure implements Exception {
  const StorageFailure(this.message, {this.statusCode});

  final String message;
  final String? statusCode;

  @override
  String toString() => 'StorageFailure($message, status: $statusCode)';
}

/// The object already exists and the upload did not ask to replace it.
class StorageConflict extends StorageFailure {
  const StorageConflict(super.message, {super.statusCode});
}
