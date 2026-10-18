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

  test('a sign-up carries the ticked age and terms box', () async {
    final httpClient = _RecordingHttpClient(
      responses: [
        http.Response(
          jsonEncode({
            'id': 'user-1',
            'aud': 'authenticated',
            'email': 'ada@example.com',
            'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{},
            'created_at': '2026-10-16T00:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ],
    );
    var ticked = true;
    final repository = SupabaseAuthRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        httpClient: httpClient,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      ),
      consent: () => ticked,
    );

    await repository.signUp('ada@example.com', 'secret123', 'ada', 'Ada');

    var body =
        jsonDecode((httpClient.requests.single as http.Request).body)
            as Map<String, dynamic>;
    expect((body['data'] as Map)['accepted_terms'], isTrue);

    ticked = false;
    await repository.signUp('ada@example.com', 'secret123', 'ada', 'Ada');
    body =
        jsonDecode((httpClient.requests.last as http.Request).body)
            as Map<String, dynamic>;
    expect((body['data'] as Map).containsKey('accepted_terms'), isFalse);
  });

  test('the profile made after sign-up records the agreement', () async {
    final httpClient = _RecordingHttpClient(
      responses: [
        http.Response('[]', 200, headers: {'content-type': 'application/json'}),
        http.Response('', 201),
      ],
    );
    final repository = SupabaseAuthRepository(
      await _clientWithSession(
        metadata: {
          'username': 'ada',
          'display_name': 'Ada Lovelace',
          'accepted_terms': true,
        },
        httpClient: httpClient,
      ),
    );

    await repository.ensureCurrentUserProfile();

    final insert =
        jsonDecode((httpClient.requests.last as http.Request).body)
            as Map<String, dynamic>;
    expect(httpClient.requests.last.method, 'POST');
    expect(insert['accepted_terms_at'], isA<String>());
    expect(insert['age_confirmed_at'], isA<String>());
  });

  test('a profile without the box ticked records nothing', () async {
    final httpClient = _RecordingHttpClient(
      responses: [
        http.Response('[]', 200, headers: {'content-type': 'application/json'}),
        http.Response('', 201),
      ],
    );
    final repository = SupabaseAuthRepository(
      await _clientWithSession(
        metadata: {'username': 'ada', 'display_name': 'Ada Lovelace'},
        httpClient: httpClient,
      ),
    );

    await repository.ensureCurrentUserProfile();

    final insert =
        jsonDecode((httpClient.requests.last as http.Request).body)
            as Map<String, dynamic>;
    expect(insert.containsKey('accepted_terms_at'), isFalse);
    expect(insert.containsKey('age_confirmed_at'), isFalse);
  });

  test('sign-up confirmation emails link back to the web app', () async {
    final httpClient = _RecordingHttpClient(
      responses: [
        http.Response(
          jsonEncode({
            'id': 'user-1',
            'aud': 'authenticated',
            'email': 'ada@example.com',
            'app_metadata': <String, dynamic>{},
            'user_metadata': <String, dynamic>{},
            'created_at': '2026-10-16T00:00:00Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ],
    );
    final repository = SupabaseAuthRepository(
      SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        httpClient: httpClient,
        authOptions: const AuthClientOptions(
          authFlowType: AuthFlowType.implicit,
        ),
      ),
      redirectUrl: () => 'https://wecord.jokebear.fyi',
    );

    await repository.signUp('ada@example.com', 'secret123', ' Ada ', ' Ada ');

    final request = httpClient.requests.single;
    expect(request.url.path, '/auth/v1/signup');
    expect(
      request.url.queryParameters['redirect_to'],
      'https://wecord.jokebear.fyi',
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
  _RecordingHttpClient({required this._responses});

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
