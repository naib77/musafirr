import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musafir/services/storage/routing_storage_provider.dart';
import 'package:musafir/services/storage/s3_storage_provider.dart';
import 'package:musafir/services/storage/storage_provider.dart';

/// Pins the coexistence rules (plan §8): the server decides which buckets
/// write to S3, a rollback mid-session lands on Supabase, reads fall back,
/// deletes hit both stores.

class _Legacy implements StorageProvider {
  final calls = <String>[];
  Object? removeFails;

  @override
  Future<String?> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required bool upsert,
  }) async {
    calls.add('upload $bucket/$path');
    return null;
  }

  @override
  String publicUrl(String bucket, String path) => 'supabase:$bucket/$path';

  @override
  Future<String> signedUrl(String bucket, String path,
      {required int expiresIn}) async {
    calls.add('sign $bucket/$path');
    return 'supabase-signed:$path';
  }

  @override
  Future<void> remove(String bucket, List<String> paths) async {
    calls.add('remove $bucket/${paths.join(',')}');
    if (removeFails != null) throw removeFails!;
  }
}

/// A scripted signer: answers by action, records every body.
class _Signer {
  final bodies = <Map<String, dynamic>>[];
  Set<String> routed = {'avatars'};
  int configCalls = 0;
  SignerError? beginFails;
  List<Map<String, dynamic>> readItems = [];
  bool down = false;

  Future<Map<String, dynamic>> call(Map<String, dynamic> body) async {
    bodies.add(body);
    if (down) throw SignerError(503, null, 'down');
    switch (body['action']) {
      case 'config':
        configCalls++;
        return {'write_buckets': routed.toList()};
      case 'begin':
        if (beginFails != null) throw beginFails!;
        return {
          'intent_id': 'i1',
          'upload': {
            'url': 'http://s3/staging',
            'fields': {'key': 'staging/k', 'Content-Type': body['mime_type']},
          },
        };
      case 'finalize':
        return {'url': 'http://signer/media/avatars/u.webp?g=1'};
      case 'read':
        return {'items': readItems};
      case 'delete':
        return {'deleted': false};
    }
    throw StateError('unexpected ${body['action']}');
  }
}

void main() {
  late _Signer signer;
  late _Legacy legacy;
  late List<http.BaseRequest> posts;
  late RoutingStorageProvider router;

  setUp(() {
    signer = _Signer();
    legacy = _Legacy();
    posts = [];
    final s3Http = MockClient.streaming((req, body) async {
      posts.add(req);
      await body.drain<void>();
      return http.StreamedResponse(const Stream.empty(), 204);
    });
    router = RoutingStorageProvider(
      s3: S3StorageProvider(
          signerUrl: 'http://signer', call: signer.call, httpClient: s3Http),
      legacy: legacy,
    );
  });

  Future<String?> upload(String bucket, {bool upsert = true}) => router.upload(
      bucket: bucket,
      path: 'u.webp',
      bytes: Uint8List.fromList([1, 2, 3]),
      contentType: 'image/webp',
      upsert: upsert);

  test('a routed bucket goes begin -> POST -> finalize and keeps its URL',
      () async {
    final url = await upload('avatars');
    expect(url, 'http://signer/media/avatars/u.webp?g=1');
    expect(
        signer.bodies.map((b) => b['action']), ['config', 'begin', 'finalize']);
    final begin = signer.bodies[1];
    expect(begin['size_bytes'], 3);
    expect(begin['mime_type'], 'image/webp');
    expect(begin['idempotency_key'], isNotEmpty);
    expect(posts.single.url.toString(), 'http://s3/staging');
    expect(legacy.calls, isEmpty);
  });

  test('the multipart body sends the policy fields before the file', () async {
    late String body;
    final s3Http = MockClient.streaming((req, stream) async {
      body = utf8.decode(await stream.toBytes(), allowMalformed: true);
      return http.StreamedResponse(const Stream.empty(), 204);
    });
    final s3 = S3StorageProvider(
        signerUrl: 'http://signer', call: signer.call, httpClient: s3Http);
    await s3.upload(
        bucket: 'avatars',
        path: 'a/u.webp',
        bytes: Uint8List.fromList([1]),
        contentType: 'image/webp',
        upsert: true);
    expect(body.indexOf('name="key"'), lessThan(body.indexOf('name="file"')));
    expect(body, contains('content-type: image/webp'));
  });

  test('an unrouted bucket stays on Supabase', () async {
    expect(await upload('documents'), isNull);
    expect(legacy.calls, ['upload documents/u.webp']);
    expect(posts, isEmpty);
  });

  test('config is cached, not fetched per upload', () async {
    await upload('avatars');
    await upload('avatars');
    expect(signer.configCalls, 1);
  });

  test('a rollback mid-session (421) lands the upload on Supabase', () async {
    signer.beginFails =
        SignerError(421, 'storage_not_routed', 'Uploads go to Supabase');
    expect(await upload('avatars'), isNull);
    expect(legacy.calls, ['upload avatars/u.webp']);
    expect(signer.configCalls, 2, reason: 'config re-read after 421');
  });

  test('an unreachable signer means Supabase, not a failed upload', () async {
    signer.down = true;
    expect(await upload('avatars'), isNull);
    expect(legacy.calls, ['upload avatars/u.webp']);
  });

  test('storage_exists is a StorageConflict (face evidence relies on it)',
      () async {
    signer.beginFails = SignerError(409, 'storage_exists', 'exists');
    await expectLater(
        upload('avatars', upsert: false), throwsA(isA<StorageConflict>()));
  });

  test('other refusals surface, they do not silently fall back', () async {
    signer.beginFails = SignerError(403, 'storage_denied', 'no');
    await expectLater(upload('avatars'), throwsA(isA<SignerError>()));
    expect(legacy.calls, isEmpty);
  });

  test('reads: S3 when it has the object, Supabase otherwise', () async {
    signer.readItems = [
      {'bucket': 'documents', 'path': 'p', 'url': 's3-signed'}
    ];
    expect(
        await router.signedUrl('documents', 'p', expiresIn: 60), 's3-signed');
    signer.readItems = [];
    expect(await router.signedUrl('documents', 'p', expiresIn: 60),
        'supabase-signed:p');
    expect(legacy.calls, ['sign documents/p']);
  });

  test('delete hits both stores even when one fails, then reports it',
      () async {
    legacy.removeFails = const StorageFailure('boom');
    await expectLater(router.remove('avatars', ['a.png', 'a.jpg']),
        throwsA(isA<StorageFailure>()));
    expect(signer.bodies.where((b) => b['action'] == 'delete').length, 2);
    expect(legacy.calls, ['remove avatars/a.png,a.jpg']);
  });

  test('a rejected S3 POST is a StorageFailure carrying the S3 code', () async {
    final s3 = S3StorageProvider(
      signerUrl: 'http://signer',
      call: signer.call,
      httpClient: MockClient((_) async =>
          http.Response('<Error><Code>EntityTooLarge</Code></Error>', 400)),
    );
    await expectLater(
        s3.upload(
            bucket: 'avatars',
            path: 'u.webp',
            bytes: Uint8List.fromList([1]),
            contentType: 'image/webp',
            upsert: true),
        throwsA(isA<StorageFailure>()
            .having((e) => e.message, 'message', contains('EntityTooLarge'))));
    expect(signer.bodies.map((b) => b['action']), isNot(contains('finalize')));
  });

  test('publicUrl encodes each segment under /media', () {
    final s3 = S3StorageProvider(signerUrl: 'http://signer', call: signer.call);
    expect(s3.publicUrl('listing-images', 'l1/a b.jpg'),
        'http://signer/media/listing-images/l1/a%20b.jpg');
  });
}
