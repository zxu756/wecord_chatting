import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/ai/actions/extracted_action.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The minutes the `ai` function's `meeting_recap` wrote (E1).
@immutable
class MeetingRecap {
  const MeetingRecap({
    required this.title,
    required this.summary,
    required this.decisions,
    required this.actionItems,
    this.truncated = false,
  });

  final String title;

  /// The key points, in the order they came up.
  final List<String> summary;
  final List<String> decisions;

  /// To-dos and events, in the shape the "To-dos from the chat" sheet reads
  /// (F4), so they become tasks the same way.
  final List<ExtractedAction> actionItems;

  /// The call was too long to be read whole; its middle was left out.
  final bool truncated;

  bool get isEmpty =>
      summary.isEmpty && decisions.isEmpty && actionItems.isEmpty;
}

/// Writes the minutes of a call from the sentences its captions collected.
/// Throws an [AiException] when the server cannot answer.
abstract interface class MeetingRecapRepository {
  Future<MeetingRecap> recap({
    required String conversationId,
    required List<Map<String, Object>> entries,
    String? language,
    DateTime? now,
  });
}

class SupabaseMeetingRecapRepository implements MeetingRecapRepository {
  const SupabaseMeetingRecapRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<MeetingRecap> recap({
    required String conversationId,
    required List<Map<String, Object>> entries,
    String? language,
    DateTime? now,
  }) async {
    final Object? data;
    try {
      final response = await _client.functions.invoke(
        'ai',
        body: {
          'action': 'meeting_recap',
          'conversation_id': conversationId,
          'entries': entries,
          'language': ?language,
          // Dates are read in the person's own zone.
          'utc_offset_minutes':
              (now ?? DateTime.now()).timeZoneOffset.inMinutes,
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
    if (data is! Map) {
      throw const AiFailedException();
    }
    List<String> texts(Object? value) => [
      if (value is List)
        for (final entry in value)
          if (entry is String && entry.trim().isNotEmpty) entry.trim(),
    ];
    return MeetingRecap(
      title: (data['title'] as String? ?? '').trim(),
      summary: texts(data['summary']),
      decisions: texts(data['decisions']),
      actionItems: [
        if (data['action_items'] is List)
          for (final item in data['action_items'] as List)
            ?ExtractedAction.maybeFromJson(item),
      ],
      truncated: data['truncated'] == true,
    );
  }
}

/// Used where there is no server (tests): AI is not set up.
class NoMeetingRecapRepository implements MeetingRecapRepository {
  const NoMeetingRecapRepository();

  @override
  Future<MeetingRecap> recap({
    required String conversationId,
    required List<Map<String, Object>> entries,
    String? language,
    DateTime? now,
  }) => Future.error(const AiNotConfiguredException());
}

final meetingRecapRepositoryProvider = Provider<MeetingRecapRepository>((ref) {
  try {
    return SupabaseMeetingRecapRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoMeetingRecapRepository();
  } on Object {
    return const NoMeetingRecapRepository();
  }
});
