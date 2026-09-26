import 'package:flutter_test/flutter_test.dart';
import 'package:mime/mime.dart';
import 'package:musafir/services/image_upload_service.dart';

/// The `chat-attachments` bucket's mime allowlist, as migration 138 sets it.
/// Duplicated here on purpose: the picker's extension list and the bucket's
/// allowlist are two halves of one rule, and the only way to notice them
/// drifting apart is to hold them side by side.
const bucketAllowlist = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'text/plain',
};

void main() {
  group('chat attachment picker', () {
    test('offers only files the bucket will accept', () {
      for (final ext in ImageUploadService.chatAttachmentExtensions) {
        final mime = lookupMimeType('attachment.$ext');
        expect(mime, isNotNull, reason: '.$ext has no known mime type');
        expect(bucketAllowlist, contains(mime),
            reason: '.$ext ($mime) would be refused by the bucket');
      }
    });

    test('never offers something that runs', () {
      // The picker used to be FileType.any; an .apk went up and was handed
      // to the other party as a download (QA round 2, scenario 45).
      for (final bad in ['apk', 'exe', 'sh', 'bat', 'js', 'html', 'svg']) {
        expect(
            ImageUploadService.chatAttachmentExtensions, isNot(contains(bad)));
      }
    });
  });
}
