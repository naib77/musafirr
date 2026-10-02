import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'storage_provider.dart';

/// [StorageProvider] over Supabase Storage — the only provider today, and the
/// one kept through coexistence and rollback.
///
/// Every call is the one the services used to make inline; the only change is
/// that a [StorageException] leaves as a [StorageFailure], so nothing above
/// this file names a Supabase type.
class SupabaseStorageProvider implements StorageProvider {
  SupabaseStorageProvider({SupabaseClient? client}) : _providedClient = client;

  final SupabaseClient? _providedClient;

  // Resolved per call rather than at construction: the services that hold
  // this are created before `Supabase.initialize` in some test and boot paths.
  SupabaseStorageClient get _storage =>
      (_providedClient ?? Supabase.instance.client).storage;

  @override
  Future<void> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required bool upsert,
  }) =>
      _guard(() => _storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: upsert),
          ));

  @override
  String publicUrl(String bucket, String path) =>
      _storage.from(bucket).getPublicUrl(path);

  @override
  Future<String> signedUrl(
    String bucket,
    String path, {
    required int expiresIn,
  }) =>
      _guard(() => _storage.from(bucket).createSignedUrl(path, expiresIn));

  @override
  Future<void> remove(String bucket, List<String> paths) =>
      _guard(() => _storage.from(bucket).remove(paths));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on StorageException catch (e) {
      throw isConflict(e)
          ? StorageConflict(e.message, statusCode: e.statusCode)
          : StorageFailure(e.message, statusCode: e.statusCode);
    }
  }

  /// Supabase has reported "already exists" both as HTTP 409 and as a 400
  /// whose `error` is `Duplicate`, depending on the storage-api version; the
  /// face submit has always accepted either.
  @visibleForTesting
  static bool isConflict(StorageException e) =>
      e.statusCode == '409' || e.error == 'Duplicate';
}
