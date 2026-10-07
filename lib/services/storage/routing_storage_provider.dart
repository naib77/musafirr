import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';
import 's3_storage_provider.dart';
import 'storage_provider.dart';

/// Coexistence (plan §8): new uploads go wherever the SERVER says for that
/// bucket; reads and deletes try S3 first and fall back to Supabase, because
/// rows written before the cutover still name Supabase objects.
///
/// NOT the default since 2026-10-07 — see [defaultStorageProvider]. Kept as the
/// explicit rollback path (construct it with a [SupabaseStorageProvider] as
/// `legacy`) and for the e2e suite.
///
/// The server's routing (`S3_WRITE_BUCKETS`, read through the signer's
/// `config` action) is the switch, not this build: moving a bucket to S3 or
/// back is a secret change, not an app release. A build that cannot reach
/// the signer writes to Supabase — the known-good path — rather than failing.
class RoutingStorageProvider implements StorageProvider {
  RoutingStorageProvider({
    required this.s3,
    required this.legacy,
    this.configTtl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final S3StorageProvider s3;
  final StorageProvider legacy;
  final Duration configTtl;
  final DateTime Function() _now;

  Set<String>? _routes;
  DateTime? _fetchedAt;
  Future<Set<String>>? _inFlight;

  @visibleForTesting
  Future<Set<String>> routes({bool refresh = false}) {
    final at = _fetchedAt;
    if (!refresh &&
        _routes != null &&
        at != null &&
        _now().difference(at) < configTtl) {
      return Future.value(_routes);
    }
    return _inFlight ??= s3.writeBuckets().then((r) {
      _routes = r;
      _fetchedAt = _now();
      return r;
    }, onError: (Object e) {
      // Unreachable signer: route nothing to S3 for now, but do not cache
      // that for the full TTL — retry on the next upload.
      debugPrint('[storage] signer config unavailable: $e');
      _routes = const {};
      _fetchedAt = _now().subtract(configTtl);
      return const <String>{};
    }).whenComplete(() => _inFlight = null);
  }

  @override
  Future<String?> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required bool upsert,
  }) async {
    if ((await routes()).contains(bucket)) {
      try {
        return await s3.upload(
            bucket: bucket,
            path: path,
            bytes: bytes,
            contentType: contentType,
            upsert: upsert);
      } on SignerError catch (e) {
        if (!e.notRouted) rethrow;
        // Rolled back since we read the config. Nothing was staged (begin
        // refuses before issuing a ticket), so Supabase is safe to use.
        await routes(refresh: true);
      }
    }
    return legacy.upload(
        bucket: bucket,
        path: path,
        bytes: bytes,
        contentType: contentType,
        upsert: upsert);
  }

  /// Supabase's URL. An S3 object's durable URL is what [upload] returned,
  /// and that is what rows store.
  @override
  String publicUrl(String bucket, String path) =>
      legacy.publicUrl(bucket, path);

  @override
  Future<String> signedUrl(
    String bucket,
    String path, {
    required int expiresIn,
  }) async {
    try {
      return await s3.signedUrl(bucket, path, expiresIn: expiresIn);
    } on StorageFailure catch (e) {
      // Not on S3 is the common case during coexistence. Any other signer
      // failure also falls back: if the object really is S3-only, Supabase
      // answers "not found", which is no worse than the signer's error.
      if (e is! StorageNotOnS3) debugPrint('[storage] S3 read failed: $e');
      return legacy.signedUrl(bucket, path, expiresIn: expiresIn);
    }
  }

  /// Both stores: a path may exist in either, and removing a missing object
  /// is quiet in both. Both are attempted even if one fails, so a signer
  /// outage cannot keep a Supabase object alive; the first failure is raised.
  @override
  Future<void> remove(String bucket, List<String> paths) async {
    Object? first;
    StackTrace? firstTrace;
    for (final op in [
      () => s3.remove(bucket, paths),
      () => legacy.remove(bucket, paths),
    ]) {
      try {
        await op();
      } catch (e, st) {
        first ??= e;
        firstTrace ??= st;
      }
    }
    if (first != null) Error.throwWithStackTrace(first, firstTrace!);
  }
}

/// The storage signer this build talks to: the signer of whichever project
/// the build points at (`{SupabaseConfig.url}/functions/v1/storage-signer`),
/// or the local one in a local-stack debug run
/// ([SupabaseConfig.useLocalStack]). Override with
/// `--dart-define=STORAGE_SIGNER_URL=…`; there is no Supabase-only build any
/// more, so an empty value is a configuration error, not a mode.
const String kStorageSignerUrl = String.fromEnvironment(
  'STORAGE_SIGNER_URL',
  defaultValue: SupabaseConfig.useLocalStack
      ? SupabaseConfig.localSignerUrl
      : '${SupabaseConfig.url}/functions/v1/storage-signer',
);

StorageProvider? _shared;

/// The provider every service should use: S3 through the signer, and only
/// that. Decided 2026-10-07: every build — release, Android, and a plain
/// `flutter run -d chrome` — stores on S3, and nothing falls back to Supabase
/// Storage. Falling back is what hid problems before (a signer that was not
/// running, a bucket not yet switched on), so a bucket the server has not
/// enabled in `S3_WRITE_BUCKETS` now fails the upload with the signer's 421
/// instead of quietly landing in Supabase. [RoutingStorageProvider] is kept
/// only for an explicit rollback; nothing constructs it by default.
///
/// Rows written before the cutover still name Supabase public URLs; those are
/// plain image URLs, not storage calls, and are rewritten in the plan's step 5.
StorageProvider defaultStorageProvider({SupabaseClient? client}) {
  if (kStorageSignerUrl.isEmpty) {
    throw StateError('STORAGE_SIGNER_URL is empty: storage needs the signer');
  }
  if (client == null && _shared != null) return _shared!;
  SupabaseClient c() => client ?? Supabase.instance.client;
  final provider = S3StorageProvider(
    signerUrl: kStorageSignerUrl,
    call: httpSignerCall(
      signerUrl: kStorageSignerUrl,
      anonKey: SupabaseConfig.anonKey,
      // Read per call: the session refreshes underneath us.
      accessToken: () => c().auth.currentSession?.accessToken,
    ),
  );
  if (client == null) _shared = provider;
  return provider;
}
