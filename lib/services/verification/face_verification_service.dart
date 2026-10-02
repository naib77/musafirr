import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../storage/storage_provider.dart';
import '../storage/supabase_storage_provider.dart';

class FaceAttempt {
  const FaceAttempt(
      {required this.id,
      required this.userId,
      required this.nonce,
      required this.method,
      required this.actions});
  final String id, userId, nonce, method;
  final List<String> actions;
  factory FaceAttempt.fromJson(Map<String, dynamic> json) => FaceAttempt(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      nonce: json['nonce'] as String,
      method: json['method'] as String,
      actions: List<String>.from(json['actions'] as List));
  Map<String, dynamic> captureConfig(String brand) => {
        'nonce': nonce,
        'method': method,
        'actions': actions,
        'brand': brand,
      };
}

class FaceCapture {
  const FaceCapture({required this.selfie, this.clip, this.extension = 'webm'});
  final Uint8List selfie;
  final Uint8List? clip;
  final String extension;

  /// Both bridges accept only the current capture. These checks bound memory;
  /// they do not make client media or gesture results trusted evidence.
  static FaceCapture? fromMessage(String message, FaceAttempt attempt) {
    if (message.length > 12000000) {
      throw const FormatException('Capture too large');
    }
    final data = jsonDecode(message) as Map<String, dynamic>;
    if (data['nonce'] != attempt.nonce || data['type'] != 'complete') {
      return null;
    }
    if (data['method'] != attempt.method) {
      throw const FormatException('Capture method changed');
    }
    final photo = base64Decode(data['selfie'] as String);
    final clip =
        data['clip'] == null ? null : base64Decode(data['clip'] as String);
    final extension = data['extension'] as String? ?? 'webm';
    if (photo.length < 100 ||
        photo.length > 524288 ||
        (clip != null && (clip.length < 100 || clip.length > 8388608)) ||
        (attempt.method == 'guided' && clip == null) ||
        !['webm', 'mp4'].contains(extension)) {
      throw const FormatException('Invalid capture');
    }
    return FaceCapture(selfie: photo, clip: clip, extension: extension);
  }
}

abstract class FaceVerificationRepository {
  Future<Map<String, dynamic>> status();
  Future<FaceAttempt> start({required bool manual});
  Future<void> submit(FaceAttempt attempt, FaceCapture capture);
}

/// The app can be deployed before the face-review database migration.
/// This is unavailable status, never evidence of approval or eligibility.
class FaceReviewUnavailable implements Exception {
  const FaceReviewUnavailable();
}

class FaceVerificationService implements FaceVerificationRepository {
  FaceVerificationService({SupabaseClient? client, StorageProvider? storage})
      : _providedClient = client,
        _storage = storage ?? SupabaseStorageProvider(client: client);
  final SupabaseClient? _providedClient;
  final StorageProvider _storage;
  SupabaseClient get _client => _providedClient ?? Supabase.instance.client;
  static final instance = FaceVerificationService();

  Future<String> gateStatus(String userId) async {
    try {
      if (_client.auth.currentUser?.id != userId) return 'unavailable';
      final result = await _client.rpc('verification_overview') as Map;
      return result['status'] as String;
    } catch (_) {
      return 'unavailable';
    }
  }

  @override
  Future<Map<String, dynamic>> status() async {
    try {
      return Map<String, dynamic>.from(
          await _client.rpc('face_verification_status') as Map);
    } on PostgrestException catch (error) {
      // Only a missing endpoint means setup is incomplete. Auth/network/SQL
      // failures must remain errors, rather than masquerading as rollout state.
      if (error.code == 'PGRST202') {
        throw const FaceReviewUnavailable();
      }
      rethrow;
    }
  }

  @override
  Future<FaceAttempt> start({required bool manual}) async =>
      FaceAttempt.fromJson(Map<String, dynamic>.from(await _client.rpc(
          'start_face_verification',
          params: {'p_method': manual ? 'manual' : 'guided'}) as Map));

  @override
  Future<void> submit(FaceAttempt attempt, FaceCapture capture) async {
    if (_client.auth.currentUser?.id != attempt.userId) {
      throw StateError('Sign in again before submitting');
    }
    // The previous response may have been lost after the server committed.
    // Do not attempt another INSERT into the now-locked evidence directory.
    final existing = await _client
        .from('face_verification_attempts')
        .select('status')
        .eq('id', attempt.id)
        .single();
    if (existing['status'] == 'pending' || existing['status'] == 'approved') {
      return;
    }
    if (existing['status'] != 'draft') throw StateError('Start a new capture');
    final prefix = '${attempt.userId}/${attempt.id}';
    // INSERT only. A retry may find an already uploaded immutable object. The
    // server validates both objects before atomically accepting the attempt.
    Future<void> upload(String path, Uint8List bytes, String type) async {
      try {
        await _storage.upload(
            bucket: 'face-evidence',
            path: path,
            bytes: bytes,
            contentType: type,
            upsert: false);
      } on StorageConflict {
        // Already there from the lost-response attempt; keep that copy.
      }
    }

    await upload('$prefix/selfie.jpg', capture.selfie, 'image/jpeg');
    if (capture.clip != null) {
      await upload('$prefix/clip.${capture.extension}', capture.clip!,
          'video/${capture.extension}');
    }
    await _client.rpc('submit_face_verification', params: {
      'p_attempt_id': attempt.id,
      'p_nonce': attempt.nonce,
      'p_clip_extension': capture.clip == null ? null : capture.extension,
    });
  }
}
