import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Where a request to WeCord AI stands (a row of `ai_jobs`, which only its
/// requester can read).
class AssistantJobStatus {
  const AssistantJobStatus({required this.status, this.reason});

  /// queued, running, done, skipped, failed or limited.
  final String status;

  /// Why it was skipped, failed or limited (see migration 202610230410).
  final String? reason;

  bool get thinking => status == 'queued' || status == 'running';
  bool get answered => status == 'done';

  /// What to tell the requester when there is no answer; null when there is
  /// nothing worth saying (the question was deleted, or answered).
  String? get noAnswerText {
    if (thinking || answered) {
      return null;
    }
    return switch (reason) {
      'circle_off' => tr('AI features are turned off in this circle.'),
      'group_off' => tr('The group owner turned off WeCord AI here.'),
      'user_off' => tr(
        'AI features are turned off. You can turn them on in Settings.',
      ),
      'limit' => tr("You've reached today's AI limit. It resets tomorrow."),
      'rate_limited' => tr(
        'You asked too quickly. Wait a moment and try again.',
      ),
      'message_gone' || 'stale' || 'not_member' => null,
      _ => tr("WeCord AI couldn't answer. Try again."),
    };
  }
}

/// The WeCord AI assistant: the state of a request, and the group owner's
/// switch.
abstract interface class AssistantRepository {
  /// The job for the message [messageId] the person sent; null when there is
  /// none (it did not mention the assistant, or was held, or is old).
  Future<AssistantJobStatus?> jobStatus(String messageId);

  /// Whether the assistant answers in the group (on unless the owner turned
  /// it off).
  Future<bool> groupAssistantEnabled(String conversationId);

  /// The owner of a group allows or forbids the assistant in it.
  Future<void> setGroupAssistantEnabled(
    String conversationId, {
    required bool enabled,
  });
}

class SupabaseAssistantRepository implements AssistantRepository {
  const SupabaseAssistantRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<AssistantJobStatus?> jobStatus(String messageId) async {
    final row = await _client
        .from('ai_jobs')
        .select('status,reason')
        .eq('message_id', messageId)
        .maybeSingle();
    if (row == null) {
      return null;
    }
    return AssistantJobStatus(
      status: row['status'] as String? ?? 'queued',
      reason: row['reason'] as String?,
    );
  }

  @override
  Future<bool> groupAssistantEnabled(String conversationId) async {
    final data = await _client.rpc<Object?>(
      'get_group_ai_assistant',
      params: {'target_conversation_id': conversationId},
    );
    return data != false;
  }

  @override
  Future<void> setGroupAssistantEnabled(
    String conversationId, {
    required bool enabled,
  }) async {
    await _client.rpc<Object?>(
      'set_group_ai_assistant',
      params: {'target_conversation_id': conversationId, 'enabled': enabled},
    );
  }
}

/// Used where there is no server (tests).
class NoAssistantRepository implements AssistantRepository {
  const NoAssistantRepository();

  @override
  Future<AssistantJobStatus?> jobStatus(String messageId) async => null;

  @override
  Future<bool> groupAssistantEnabled(String conversationId) async => true;

  @override
  Future<void> setGroupAssistantEnabled(
    String conversationId, {
    required bool enabled,
  }) async {}
}

final assistantRepositoryProvider = Provider<AssistantRepository>((ref) {
  try {
    return SupabaseAssistantRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoAssistantRepository();
  } on Object {
    return const NoAssistantRepository();
  }
});

/// How long between looks at a request that is still being answered.
final assistantPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

/// The state of the request made by the message [messageId], looked at every
/// few seconds until it is answered or given up on (or about 90 seconds).
final assistantJobProvider = StreamProvider.autoDispose
    .family<AssistantJobStatus?, String>((ref, messageId) async* {
      final repository = ref.watch(assistantRepositoryProvider);
      final interval = ref.watch(assistantPollIntervalProvider);
      for (var attempt = 0; attempt < 30; attempt++) {
        final AssistantJobStatus? status;
        try {
          status = await repository.jobStatus(messageId);
        } on Object {
          return;
        }
        yield status;
        if (status == null || !status.thinking) {
          return;
        }
        await Future<void>.delayed(interval);
      }
    });

/// Whether WeCord AI answers in the group [conversationId].
final groupAssistantEnabledProvider = FutureProvider.autoDispose
    .family<bool, String>(
      (ref, conversationId) => ref
          .watch(assistantRepositoryProvider)
          .groupAssistantEnabled(conversationId),
    );
