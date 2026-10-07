import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:musafir/services/storage/routing_storage_provider.dart';
import 'package:musafir/services/storage/s3_storage_provider.dart';
import 'package:musafir/services/storage/storage_provider.dart';
import 'package:uuid/uuid.dart';

/// The real app provider against a real signer + MinIO + local Supabase.
/// Skipped unless pointed at one, so `flutter test` stays offline:
///
///   sh tool/storage_local.sh            # MinIO
///   (run the signer locally; see docs/plans/aws-s3-storage-migration.md)
///   STORAGE_E2E_SIGNER=http://127.0.0.1:8000/storage-signer \
///   STORAGE_E2E_ANON=… STORAGE_E2E_JWT=(a session JWT for host 1111…) \
///   flutter test test/services/storage/storage_minio_e2e_test.dart
///
/// Uses the seed host (owner of listing aaaaaaaa-…-0002).
void main() {
  final env = Platform.environment;
  final signerUrl = env['STORAGE_E2E_SIGNER'];
  final skip = signerUrl == null ? 'STORAGE_E2E_SIGNER not set' : null;
  const host = '11111111-1111-1111-1111-111111111111';

  late S3StorageProvider s3;
  late RoutingStorageProvider router;
  final client = http.Client();

  setUpAll(() {
    if (signerUrl == null) return;
    s3 = S3StorageProvider(
      signerUrl: signerUrl,
      call: httpSignerCall(
        signerUrl: signerUrl,
        anonKey: env['STORAGE_E2E_ANON']!,
        accessToken: () => env['STORAGE_E2E_JWT'],
      ),
    );
    router = RoutingStorageProvider(s3: s3, legacy: _NoLegacy());
  });

  Uint8List padded(List<int> head, [int size = 600]) =>
      Uint8List.fromList([...head, ...List.filled(size - head.length, 0)]);
  final webp =
      padded([...ascii.encode('RIFF'), 0, 0, 0, 0, ...ascii.encode('WEBP')]);
  final jpeg = padded([0xff, 0xd8, 0xff, 0xe0]);
  final pdf = padded(ascii.encode('%PDF-1.7\n'));

  Future<Uint8List> fetch(String url) async {
    final res = await client.get(Uri.parse(url));
    expect(res.statusCode, 200, reason: url);
    return res.bodyBytes;
  }

  test('avatar: upload lands in MinIO, the stored URL serves the bytes',
      () async {
    final url = await router.upload(
        bucket: 'avatars',
        path: '$host.webp',
        bytes: webp,
        contentType: 'image/webp',
        upsert: true);
    expect(url, startsWith('$signerUrl/media/avatars/$host.webp?g='));
    expect(await fetch(url!), webp);

    // A replace is a new generation, so the stored URL changes (cache bust).
    final again = await router.upload(
        bucket: 'avatars',
        path: '$host.webp',
        bytes: webp,
        contentType: 'image/webp',
        upsert: true);
    expect(again, isNot(url));
  }, skip: skip);

  test('listing image: upload, public read, delete', () async {
    final path =
        'aaaaaaaa-0000-0000-0000-000000000002/e2e_${const Uuid().v4()}.jpg';
    final url = await router.upload(
        bucket: 'listing-images',
        path: path,
        bytes: jpeg,
        contentType: 'image/jpeg',
        upsert: true);
    expect(await fetch(url!), jpeg);
    await router.remove('listing-images', [path]);
    final gone = await client.get(Uri.parse(url));
    expect(gone.statusCode, 404);
  }, skip: skip);

  test('document: private, readable only through a signed URL', () async {
    final path = '$host/trade_licence/${const Uuid().v4()}.pdf';
    final url = await router.upload(
        bucket: 'documents',
        path: path,
        bytes: pdf,
        contentType: 'application/pdf',
        upsert: true);
    expect(url, isNot(contains('/media/')), reason: 'never a public URL');
    final signed = await router.signedUrl('documents', path, expiresIn: 60);
    expect(await fetch(signed), pdf);
    final media = await client.get(Uri.parse(s3.publicUrl('documents', path)));
    expect(media.statusCode, 404, reason: 'private buckets are not served');

    await router.remove('documents', [path]);
    await expectLater(s3.signedUrl('documents', path, expiresIn: 60),
        throwsA(isA<StorageNotOnS3>()));
  }, skip: skip);

  test('NID evidence is write-once: a second upload is a conflict', () async {
    final path = '$host/nid/${const Uuid().v4()}/front.jpg';
    Future<String?> put() => router.upload(
        bucket: 'documents',
        path: path,
        bytes: jpeg,
        contentType: 'image/jpeg',
        upsert: false);
    await put();
    await expectLater(put(), throwsA(isA<StorageConflict>()));
  }, skip: skip);

  test('bytes that are not the declared type are refused at finalize',
      () async {
    await expectLater(
        router.upload(
            bucket: 'avatars',
            path: '$host.jpg',
            bytes: padded(ascii.encode('<html>')),
            contentType: 'image/jpeg',
            upsert: true),
        throwsA(isA<SignerError>()
            .having((e) => e.hint, 'hint', 'storage_invalid')));
  }, skip: skip);
}

/// Every test bucket is routed to S3; touching Supabase would be a bug.
class _NoLegacy implements StorageProvider {
  @override
  Future<String?> upload(
          {required String bucket,
          required String path,
          required Uint8List bytes,
          required String contentType,
          required bool upsert}) =>
      throw StateError('fell back to Supabase for $bucket');

  @override
  String publicUrl(String bucket, String path) => throw StateError('legacy');

  @override
  Future<String> signedUrl(String bucket, String path,
          {required int expiresIn}) =>
      throw StorageFailure('not on Supabase either');

  // Removal fans out to both stores; the legacy half is a no-op here.
  @override
  Future<void> remove(String bucket, List<String> paths) async {}
}
