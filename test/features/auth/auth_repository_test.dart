import 'dart:convert';

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
  });
}

Future<SupabaseClient> _clientWithSession({
  required Map<String, dynamic> metadata,
}) async {
  final client = SupabaseClient('https://example.supabase.co', 'test-anon-key');
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
