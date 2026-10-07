import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/image_upload_service.dart';
import 'package:musafir/services/storage/storage_provider.dart';
import 'package:musafir/services/storage/storage_url.dart';
import 'package:musafir/services/storage/supabase_storage_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records every call; fails on demand. Stage 1 of the S3 plan is "same
/// behaviour, behind a seam", so these tests pin what the services ask the
/// transport for — the S3 provider must satisfy the same expectations.
class _FakeStorage implements StorageProvider {
  final calls = <String>[];
  StorageFailure? failWith;
  String? storedUrl;

  @override
  Future<String?> upload({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
    required bool upsert,
  }) async {
    calls.add('upload $bucket/$path $contentType upsert=$upsert');
    if (failWith != null) throw failWith!;
    return storedUrl;
  }

  @override
  String publicUrl(String bucket, String path) =>
      'https://x.supabase.co/storage/v1/object/public/$bucket/$path';

  @override
  Future<String> signedUrl(String bucket, String path,
      {required int expiresIn}) async {
    calls.add('sign $bucket/$path $expiresIn');
    if (failWith != null) throw failWith!;
    return 'signed:$path';
  }

  @override
  Future<void> remove(String bucket, List<String> paths) async {
    calls.add('remove $bucket/${paths.join(',')}');
    if (failWith != null) throw failWith!;
  }
}

void main() {
  group('storagePathFromUrl', () {
    const bucket = 'listing-images';
    const base = 'https://bojkmonskqlhuakxhzcb.supabase.co/storage/v1';

    test('public object URL gives the uploaded key', () {
      expect(
        storagePathFromUrl('$base/object/public/$bucket/abc/1_x.webp',
            bucket: bucket),
        'abc/1_x.webp',
      );
    });

    test('hotel property_ folder keeps its prefix', () {
      expect(
        storagePathFromUrl('$base/object/public/$bucket/property_9/a.jpg',
            bucket: bucket),
        'property_9/a.jpg',
      );
    });

    test('query and fragment are not part of the key', () {
      // The old parser returned `abc/a.jpg?t=1`, so the delete missed.
      expect(
        storagePathFromUrl('$base/object/public/$bucket/abc/a.jpg?t=1#f',
            bucket: bucket),
        'abc/a.jpg',
      );
    });

    test('percent-encoded segments decode to the stored key', () {
      expect(
        storagePathFromUrl('$base/object/public/$bucket/abc/a%20b.jpg',
            bucket: bucket),
        'abc/a b.jpg',
      );
    });

    test('signed and render URLs of the bucket resolve', () {
      expect(
        storagePathFromUrl('$base/object/sign/$bucket/abc/a.jpg?token=t',
            bucket: bucket),
        'abc/a.jpg',
      );
      expect(
        storagePathFromUrl('$base/render/image/public/$bucket/abc/a.jpg',
            bucket: bucket),
        'abc/a.jpg',
      );
    });

    test('signer media URL gives the key without the generation', () {
      const media = 'http://127.0.0.1:54321/functions/v1/storage-signer/media';
      expect(
        storagePathFromUrl('$media/$bucket/abc/a%20b.jpg?g=3', bucket: bucket),
        'abc/a b.jpg',
      );
      expect(storagePathFromUrl('$media/avatars/u.webp?g=1', bucket: bucket),
          isNull);
      expect(storagePathFromUrl('$media/$bucket/', bucket: bucket), isNull);
    });

    test('another bucket, external images and junk are not ours', () {
      for (final url in [
        '$base/object/public/avatars/u.webp',
        'https://images.example.com/listing-images/abc/a.jpg',
        'https://cdn.example.com/storage/v1/elsewhere/$bucket/a.jpg',
        '$base/object/public/$bucket/',
        '$base/object/public/$bucket',
        'listing-images/abc/a.jpg',
        '',
        'not a url',
      ]) {
        expect(storagePathFromUrl(url, bucket: bucket), isNull, reason: url);
      }
    });
  });

  group('SupabaseStorageProvider.isConflict', () {
    test('409 and Duplicate are conflicts, other failures are not', () {
      expect(
          SupabaseStorageProvider.isConflict(
              const StorageException('exists', statusCode: '409')),
          isTrue);
      expect(
          SupabaseStorageProvider.isConflict(const StorageException('exists',
              statusCode: '400', error: 'Duplicate')),
          isTrue);
      expect(
          SupabaseStorageProvider.isConflict(
              const StorageException('too big', statusCode: '413')),
          isFalse);
    });
  });

  group('ImageUploadService over the seam', () {
    late _FakeStorage fake;
    late StorageProvider original;
    final service = ImageUploadService.instance;

    setUp(() {
      original = service.storage;
      fake = _FakeStorage();
      service.storage = fake;
    });
    tearDown(() => service.storage = original);

    test('upload overwrites and returns the public URL and key', () async {
      final dir = await Directory.systemTemp.createTemp('seam');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/proof.pdf')..writeAsBytesSync([1, 2, 3]);

      final result = await service.uploadPlatformFile(
        file: PlatformFile(name: 'proof.pdf', size: 3, path: file.path),
        bucket: StorageBuckets.documents,
        path: 'u1/address/proof.pdf',
      );

      expect(fake.calls, [
        'upload documents/u1/address/proof.pdf application/pdf upsert=true'
      ]);
      expect(result.success, isTrue);
      expect(result.storagePath, 'u1/address/proof.pdf');
      expect(
          result.publicUrl, endsWith('/public/documents/u1/address/proof.pdf'));
    });

    test('a URL minted by the provider wins over the computed one', () async {
      final dir = await Directory.systemTemp.createTemp('seam');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/p.pdf')..writeAsBytesSync([1]);
      fake.storedUrl = 'https://signer/media/documents/u1/p.pdf?g=2';

      final result = await service.uploadPlatformFile(
        file: PlatformFile(name: 'p.pdf', size: 1, path: file.path),
        bucket: StorageBuckets.documents,
        path: 'u1/p.pdf',
      );
      expect(result.publicUrl, fake.storedUrl);
    });

    test('a storage failure becomes a failed result carrying its message',
        () async {
      final dir = await Directory.systemTemp.createTemp('seam');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/a.pdf')..writeAsBytesSync([1]);
      fake.failWith = const StorageFailure('Payload too large');

      final result = await service.uploadPlatformFile(
        file: PlatformFile(name: 'a.pdf', size: 1, path: file.path),
        bucket: StorageBuckets.documents,
        path: 'u1/a.pdf',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, 'Payload too large');
    });

    test('signed document URL asks for the documents bucket and expiry',
        () async {
      expect(await service.signedDocumentUrl('u1/nid/x/front.jpeg'),
          'signed:u1/nid/x/front.jpeg');
      expect(fake.calls, ['sign documents/u1/nid/x/front.jpeg 3600']);

      fake.failWith = const StorageFailure('Object not found');
      expect(await service.signedDocumentUrl('gone'), isNull);
    });

    test('listing image delete reports failure instead of throwing', () async {
      expect(await service.deleteListingImage('abc/a.jpg'), isTrue);
      fake.failWith = const StorageFailure('denied');
      expect(await service.deleteListingImage('abc/a.jpg'), isFalse);
      expect(fake.calls, [
        'remove listing-images/abc/a.jpg',
        'remove listing-images/abc/a.jpg',
      ]);
    });

    test('avatar delete stops at the first extension that does not throw',
        () async {
      // Characterisation, not endorsement: removing a missing path is not an
      // error, so this always stops at webp. An S3 provider must keep
      // "missing is quiet" or this starts reporting false.
      expect(await service.deleteAvatar('u1'), isTrue);
      expect(fake.calls, ['remove avatars/u1.webp']);
    });
  });
}
