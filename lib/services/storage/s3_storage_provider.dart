import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:uuid/uuid.dart';

import 'storage_provider.dart';

/// One call to the storage-signer edge function: the JSON body in, the JSON
/// answer out, or a [SignerError]. A seam so the provider is testable without
/// a network, and so the default can attach the caller's session per call.
typedef SignerCall = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> body);

/// A non-2xx answer from the signer. [hint] is the machine-readable reason
/// (`storage_exists`, `storage_not_routed`, …) — branch on it, never on
/// [message], for the same reason booking conflicts branch on `hint`.
class SignerError extends StorageFailure {
  SignerError(this.status, this.hint, String message)
      : super(message, statusCode: '$status');

  final int status;
  final String? hint;

  /// The server no longer routes this bucket to S3 (a rollback, or a cohort
  /// moved back); the client's config is stale.
  bool get notRouted => status == 421 || hint == 'storage_not_routed';
}

/// The object is not on S3 (unknown, not yet migrated, or not readable by the
/// caller). The router reads that as "try Supabase".
class StorageNotOnS3 extends StorageFailure {
  const StorageNotOnS3(super.message) : super(statusCode: '404');
}

/// [StorageProvider] over S3, through the storage-signer (plan §6).
///
/// The app never holds an S3 credential and never names a physical bucket:
/// it asks the signer for a ticket (`begin`, which runs the caller's own
/// authorization RPC), POSTs the bytes straight to S3 under a policy that
/// pins key, type and exact length, then asks the signer to `finalize`, which
/// re-reads the bytes, checks them, and records the immutable object. Only
/// after finalize does the object exist for any verifier or reader.
class S3StorageProvider implements StorageProvider {
  S3StorageProvider({
    required this.signerUrl,
    required SignerCall call,
    http.Client? httpClient,
  })  : _call = call,
        _http = httpClient ?? http.Client();

  /// `…/functions/v1/storage-signer`, no trailing slash.
  final String signerUrl;
  final SignerCall _call;
  final http.Client _http;

  /// The logical buckets the server currently routes new uploads to S3 for.
  Future<Set<String>> writeBuckets() async {
    final res = await _call({'action': 'config'});
    return {...(res['write_buckets'] as List? ?? const []).cast<String>()};
  }

  @override
  Future<String?> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required bool upsert,
  }) async {
    final ticket = await _guardConflict(() => _call({
          'action': 'begin',
          'bucket': bucket,
          'path': path,
          'mime_type': contentType,
          'size_bytes': bytes.length,
          'upsert': upsert,
          // One key per upload call: a retried *request* inside this call
          // must not open a second intent, but a new call is a new upload.
          'idempotency_key': const Uuid().v4(),
        }));
    final upload = ticket['upload'] as Map<String, dynamic>;
    final fields = (upload['fields'] as Map).cast<String, String>();

    // Multipart field order matters to S3: every policy field, then `file`
    // last. http writes all `fields` before `files`, which is exactly that.
    final req = http.MultipartRequest('POST', Uri.parse(upload['url']))
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: path.split('/').last,
          contentType: MediaType.parse(contentType)));
    final posted = await _http.send(req);
    final body = await posted.stream.bytesToString();
    if (posted.statusCode < 200 || posted.statusCode >= 300) {
      // S3 answers policy violations (wrong length/type, expired) as 403
      // with an XML body; surface the code, not the XML.
      final code = RegExp(r'<Code>([^<]+)</Code>').firstMatch(body)?.group(1);
      throw StorageFailure(
          'Upload rejected by storage${code == null ? '' : ' ($code)'}',
          statusCode: '${posted.statusCode}');
    }

    final done = await _call({
      'action': 'finalize',
      'intent_id': ticket['intent_id'],
    });
    return done['url'] as String?;
  }

  /// The generation-less media URL. Only for public buckets; rows should keep
  /// the URL [upload] returned, which carries the generation.
  @override
  String publicUrl(String bucket, String path) =>
      '$signerUrl/media/$bucket/${path.split('/').map(Uri.encodeComponent).join('/')}';

  @override
  Future<String> signedUrl(
    String bucket,
    String path, {
    required int expiresIn,
  }) async {
    // The signer picks the lifetime per bucket (documents 1 h, face evidence
    // 5 min); [expiresIn] is a ceiling the caller asked for, not a demand.
    final res = await _call({
      'action': 'read',
      'refs': [
        {'bucket': bucket, 'path': path}
      ],
    });
    final items = (res['items'] as List? ?? const []).cast<Map>();
    if (items.isEmpty) throw const StorageNotOnS3('Not on S3');
    return items.first['url'] as String;
  }

  @override
  Future<void> remove(String bucket, List<String> paths) async {
    // Deleting an object that is not on S3 answers `deleted: false` quietly,
    // matching Supabase's empty-list answer that callers rely on.
    for (final path in paths) {
      await _call({'action': 'delete', 'bucket': bucket, 'path': path});
    }
  }

  Future<Map<String, dynamic>> _guardConflict(
      Future<Map<String, dynamic>> Function() call) async {
    try {
      return await call();
    } on SignerError catch (e) {
      if (e.hint == 'storage_exists') {
        throw StorageConflict(e.message, statusCode: e.statusCode);
      }
      rethrow;
    }
  }
}

/// The production [SignerCall]: POST JSON to [signerUrl] with the caller's
/// session (or the anon key when signed out — the signer then refuses
/// anything but public reads, which is the point).
SignerCall httpSignerCall({
  required String signerUrl,
  required String anonKey,
  required String? Function() accessToken,
  http.Client? client,
}) {
  final c = client ?? http.Client();
  return (body) async {
    final res = await c.post(
      Uri.parse(signerUrl),
      headers: {
        'Content-Type': 'application/json',
        'apikey': anonKey,
        'Authorization': 'Bearer ${accessToken() ?? anonKey}',
      },
      body: jsonEncode(body),
    );
    final Object? decoded;
    try {
      decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    } on FormatException {
      throw SignerError(res.statusCode, null, 'Storage service unavailable');
    }
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw SignerError(res.statusCode, map['hint'] as String?,
          map['error'] as String? ?? 'Storage error');
    }
    return map;
  };
}
