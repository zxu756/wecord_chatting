import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/notes/public/public_note.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The link is dead: unknown, withdrawn, the note deleted, the circle taken
/// down. The server says the same for all of them; so does the page.
class PublicNoteGoneException implements Exception {
  const PublicNoteGoneException();
}

/// Reads published notes. No account needed.
abstract interface class PublicNoteRepository {
  /// The note behind [token]; throws [PublicNoteGoneException] when the link
  /// is dead and another error when the server cannot be reached.
  Future<PublicNote> load(String token);
}

class SupabasePublicNoteRepository implements PublicNoteRepository {
  const SupabasePublicNoteRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PublicNote> load(String token) async {
    if (!isPublicNoteToken(token)) {
      throw const PublicNoteGoneException();
    }
    try {
      final response = await _client.functions.invoke(
        'note-public/$token',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is! Map) {
        throw StateError('Unexpected response.');
      }
      return PublicNote.fromJson(Map<String, dynamic>.from(data));
    } on FunctionException catch (error) {
      if (error.status == 404) {
        throw const PublicNoteGoneException();
      }
      rethrow;
    }
  }
}

/// Used where Supabase is not set up (tests): every link is dead.
class UninitializedPublicNoteRepository implements PublicNoteRepository {
  const UninitializedPublicNoteRepository();

  @override
  Future<PublicNote> load(String token) async =>
      throw const PublicNoteGoneException();
}

final publicNoteRepositoryProvider = Provider<PublicNoteRepository>((ref) {
  try {
    return SupabasePublicNoteRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedPublicNoteRepository();
  }
});

final publicNoteProvider = FutureProvider.autoDispose
    .family<PublicNote, String>(
      (ref, token) => ref.watch(publicNoteRepositoryProvider).load(token),
    );
