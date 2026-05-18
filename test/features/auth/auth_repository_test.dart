import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';

void main() {
  group('SupabaseAuthRepository.ensureCurrentUserProfile', () {
    test('throws when signed-in user metadata lacks username', () async {
      final repository = SupabaseAuthRepository(
        await _clientWithSession(metadata: {'display_name': 'Ada Lovelace'}),
      );

      await expectLater(
        repository.ensureCurrentUserProfile(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Profile setup is incomplete'),
          ),
        ),
      );
    });

    test('throws when signed-in user metadata lacks display name', () async {
      final repository = SupabaseAuthRepository(
        await _clientWithSession(metadata: {'username': 'ada'}),
      );

      await expectLater(
        repository.ensureCurrentUserProfile(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Profile setup is incomplete'),
          ),
        ),
      );
    });

    test(
      'throws when signed-in user metadata has empty profile fields',
      () async {
        for (final metadata in [
          {'username': ' ', 'display_name': 'Ada Lovelace'},
          {'username': 'ada', 'display_name': ' '},
        ]) {
          final repository = SupabaseAuthRepository(
            await _clientWithSession(metadata: metadata),
          );

          await expectLater(
            repository.ensureCurrentUserProfile(),
            throwsA(
              isA<StateError>().having(
                (error) => error.message,
                'message',
                contains('Profile setup is incomplete'),
              ),
            ),
          );
        }
      },
    );

    test(
      'does not upsert when the current user profile already exists',
      () async {
        final httpClient = _RecordingHttpClient(
          responses: [
            http.Response(
              jsonEncode([
                {'id': 'user-1'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ],
        );
        final repository = SupabaseAuthRepository(
          await _clientWithSession(
            metadata: {'username': 'ada', 'display_name': 'Ada Lovelace'},
            httpClient: httpClient,
          ),
        );

        await repository.ensureCurrentUserProfile();

        expect(httpClient.requests.map((request) => request.method), ['GET']);
        expect(httpClient.requests.single.url.path, '/rest/v1/profiles');
      },
    );
  });
}

Future<SupabaseClient> _clientWithSession({
  required Map<String, dynamic> metadata,
  http.Client? httpClient,
}) async {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: httpClient,
  );
  await client.auth.setInitialSession(
    jsonEncode(
      Session(
        accessToken: 'test-access-token',
        tokenType: 'bearer',
        user: User(
          id: 'user-1',
          appMetadata: const {},
          userMetadata: metadata,
          aud: 'authenticated',
          email: 'ada@example.com',
          createdAt: DateTime.utc(2026).toIso8601String(),
        ),
      ).toJson(),
    ),
  );
  return client;
}

class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient({required List<http.Response> responses})
    : _responses = responses;

  final List<http.Response> _responses;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = _responses.isEmpty
        ? http.Response('', 200)
        : _responses.removeAt(0);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
