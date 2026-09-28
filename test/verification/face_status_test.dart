import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musafir/screens/verification/identity_verification_screen.dart';
import 'package:musafir/services/verification/face_verification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('missing status RPC shows unavailable and never opens capture',
      (tester) async {
    final client = (await tester.runAsync(() async =>
        SupabaseClient('https://example.supabase.co', 'test-key',
            httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/face_verification_status');
          return http.Response(
              jsonEncode({
                'code': 'PGRST202',
                'message':
                    'Could not find the function public.face_verification_status without parameters in the schema cache',
              }),
              404,
              headers: {'content-type': 'application/json'},
              request: request);
        }))))!;
    addTearDown(() => tester.runAsync(client.dispose));
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
          home: IdentityVerificationScreen(
              userId: 'user-1',
              repository: FaceVerificationService(client: client))));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Face review is not available yet'),
        findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.text('Start face check'), findsNothing);
  });
}
