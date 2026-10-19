import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/note_assist/note_assist_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

class SupabaseNoteAssistRepository implements NoteAssistRepository {
  const SupabaseNoteAssistRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<NoteAssistResult> assist({
    required String noteId,
    required NoteAssistMode mode,
    String? text,
    NoteAssistTone? tone,
    AiLanguage? target,
    AiLanguage? language,
  }) async {
    final Object? data;
    try {
      final response = await _client.functions.invoke(
        'ai',
        body: {
          'action': 'note_assist',
          'note_id': noteId,
          'mode': mode.code,
          'text': ?text,
          if (mode == NoteAssistMode.tone && tone != null) 'tone': tone.code,
          if (mode == NoteAssistMode.translate && target != null)
            'target': target.code,
          'language': ?language?.code,
        },
      );
      data = response.data;
    } on FunctionException catch (error) {
      throw aiExceptionFor(error.status, error.details);
    } on Object catch (error) {
      if (error is AiException) {
        rethrow;
      }
      throw const AiFailedException();
    }
    if (data is! Map || data['blocks'] is! List) {
      throw const AiFailedException();
    }
    return NoteAssistResult(
      blocks: [
        for (final block in data['blocks'] as List)
          ?NoteAssistBlock.maybeFromJson(block),
      ],
      text: data['text'] as String? ?? '',
      truncated: data['truncated'] == true,
    );
  }
}

/// Used where there is no server (tests): AI is not set up.
class NoNoteAssistRepository implements NoteAssistRepository {
  const NoNoteAssistRepository();

  @override
  Future<NoteAssistResult> assist({
    required String noteId,
    required NoteAssistMode mode,
    String? text,
    NoteAssistTone? tone,
    AiLanguage? target,
    AiLanguage? language,
  }) => Future.error(const AiNotConfiguredException());
}

final noteAssistRepositoryProvider = Provider<NoteAssistRepository>((ref) {
  try {
    return SupabaseNoteAssistRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoNoteAssistRepository();
  } on Object {
    return const NoNoteAssistRepository();
  }
});
