import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../storage/storage_provider.dart';
import '../storage/supabase_storage_provider.dart';

const identityDocumentTypes = <String, String>{
  'nid': 'National ID (NID)',
  'passport': 'Passport',
  'driving_license': 'Driving License',
  'student_id': 'Student / Admission / Exam ID',
  'office_id': 'Office / Employee ID',
};

abstract class NidVerificationRepository {
  Future<Map<String, dynamic>> status();
  Future<void> submit(Uint8List front, Uint8List? back,
      {required String documentType, required String documentNumber});
}

/// Uploads both sides privately, then commits the submission atomically.
/// Retains the historical document choices; no paid provider is called.
class NidVerificationService implements NidVerificationRepository {
  NidVerificationService({StorageProvider? storage})
      : _storage = storage ?? SupabaseStorageProvider();
  final StorageProvider _storage;
  SupabaseClient get _client => Supabase.instance.client;
  @override
  Future<Map<String, dynamic>> status() async => Map<String, dynamic>.from(
      await _client.rpc('nid_verification_status') as Map);

  static String imageType(Uint8List bytes) {
    if (bytes.length < 100 || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose an image smaller than 5 MB.');
    }
    if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
      return 'jpeg';
    }
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a) {
      return 'png';
    }
    throw const FormatException('Choose a JPG or PNG image.');
  }

  @override
  Future<void> submit(Uint8List front, Uint8List? back,
      {required String documentType, required String documentNumber}) async {
    if (!identityDocumentTypes.containsKey(documentType) ||
        (documentType == 'nid' && back == null) ||
        documentNumber.trim().isEmpty) {
      throw const FormatException(
          'Choose a document and complete its required details.');
    }
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in again.');
    final types = [imageType(front), if (back != null) imageType(back)];
    final prefix = '${user.id}/nid/${const Uuid().v4()}';
    final paths = [
      '$prefix/front.${types[0]}',
      if (back != null) '$prefix/back.${types[1]}'
    ];
    for (var i = 0; i < paths.length; i++) {
      // upsert stays false, as the old default was: each submission writes a
      // fresh uuid prefix, and `/nid/` objects are not owner-replaceable.
      await _storage.upload(
          bucket: 'documents',
          path: paths[i],
          bytes: i == 0 ? front : back!,
          contentType: 'image/${types[i]}',
          upsert: false);
    }
    // A failed row write is an error, even when the Storage upload succeeded.
    await _client.rpc('submit_identity_document', params: {
      'p_front_path': paths[0],
      'p_back_path': back == null ? null : paths[1],
      'p_document_type': documentType,
      'p_document_number': documentNumber.trim(),
    });
  }
}
