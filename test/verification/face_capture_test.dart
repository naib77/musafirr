import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musafir/services/verification/face_verification_service.dart';

void main() {
  const attempt = FaceAttempt(
      id: 'a',
      userId: 'u',
      nonce: 'n',
      method: 'guided',
      actions: ['blink', 'left', 'right']);
  Map<String, dynamic> message() => {
        'nonce': 'n',
        'type': 'complete',
        'method': 'guided',
        'selfie': base64Encode(Uint8List(100)),
        'clip': base64Encode(Uint8List(100)),
        'extension': 'webm'
      };
  test('bridge ignores a different session and readiness messages', () {
    expect(
        FaceCapture.fromMessage(
            jsonEncode(message()..['nonce'] = 'other'), attempt),
        isNull);
    expect(FaceCapture.fromMessage('{"nonce":"n","type":"ready"}', attempt),
        isNull);
  });
  test('guided capture requires video and an unchanged capture method', () {
    expect(
        () => FaceCapture.fromMessage(
            jsonEncode(message()..['clip'] = null), attempt),
        throwsFormatException);
    expect(
        () => FaceCapture.fromMessage(
            jsonEncode(message()..['method'] = 'manual'), attempt),
        throwsFormatException);
  });
  test('unsupported video types and oversize photos are rejected', () {
    expect(
        () => FaceCapture.fromMessage(
            jsonEncode(message()..['extension'] = 'exe'), attempt),
        throwsFormatException);
    expect(
        () => FaceCapture.fromMessage(
            jsonEncode(message()..['selfie'] = base64Encode(Uint8List(524289))),
            attempt),
        throwsFormatException);
  });
  test('valid bounded capture is decoded', () {
    final result = FaceCapture.fromMessage(jsonEncode(message()), attempt)!;
    expect(result.selfie.length, 100);
    expect(result.clip!.length, 100);
    expect(result.extension, 'webm');
  });
}
