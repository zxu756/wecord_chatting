import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message_components.dart';

/// What the server said after a press was sent to the bot.
class InteractionReceipt {
  const InteractionReceipt({
    required this.interactionId,
    required this.botName,
    this.byCallback = false,
  });

  factory InteractionReceipt.fromJson(Map<String, dynamic> json) {
    return InteractionReceipt(
      interactionId: json['interaction_id'] as String,
      botName: json['bot_name'] as String? ?? '',
      byCallback: json['by_callback'] == true,
    );
  }

  final String interactionId;
  final String botName;

  /// The bot gets presses on its own server's address (a callback) rather
  /// than by polling.
  final bool byCallback;
}

/// Whether the bot has answered a press.
enum InteractionState { pending, answered, expired }

class InteractionStatus {
  const InteractionStatus(this.state, {this.responseKind});

  factory InteractionStatus.fromJson(Map<String, dynamic> json) {
    return InteractionStatus(switch (json['status']) {
      'answered' => InteractionState.answered,
      'expired' => InteractionState.expired,
      _ => InteractionState.pending,
    }, responseKind: json['response_kind'] as String?);
  }

  final InteractionState state;

  /// message, ephemeral, update or ack, once answered.
  final String? responseKind;
}

/// A bot's private reply: only the person who pressed sees it.
class EphemeralReply {
  const EphemeralReply({
    required this.id,
    required this.botName,
    required this.body,
    required this.createdAt,
    this.messageId,
    this.components,
  });

  static EphemeralReply? maybeFromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final id = json['id'];
    final body = json['body'];
    final createdAt = DateTime.tryParse('${json['created_at']}');
    if (id is! String || body is! String || createdAt == null) {
      return null;
    }
    return EphemeralReply(
      id: id,
      messageId: json['message_id'] as String?,
      botName: json['bot_name'] as String? ?? '',
      body: body,
      createdAt: createdAt.toUtc(),
      components: MessageComponents.maybeFromJson(json['components']),
    );
  }

  final String id;

  /// The message the person pressed on.
  final String? messageId;
  final String botName;
  final String body;
  final DateTime createdAt;
  final MessageComponents? components;
}

/// Why a press did not go through, in words for the person.
class InteractionException implements Exception {
  const InteractionException(this.kind);

  final InteractionFailure kind;

  String get message => switch (kind) {
    InteractionFailure.tooFast => tr('Too fast. Wait a moment and try again.'),
    InteractionFailure.gone => tr('This message is no longer available.'),
    InteractionFailure.notAllowed => tr('You cannot use this bot.'),
    InteractionFailure.invalid => tr('That answer is not valid. Check it.'),
    InteractionFailure.other => tr('Could not reach the bot. Try again.'),
  };

  @override
  String toString() => 'InteractionException($kind)';
}

enum InteractionFailure { tooFast, gone, notAllowed, invalid, other }

abstract interface class InteractionsRepository {
  /// Presses [componentId] of [messageId] (a message, or a private reply of
  /// a bot). [values] are the chosen option values (a list) or the form's
  /// answers (an object); null for a plain button.
  Future<InteractionReceipt> submit({
    required String messageId,
    required String componentId,
    Object? values,
  });

  Future<InteractionStatus> status(String interactionId);

  /// The bots' private replies to me in a chat.
  Future<List<EphemeralReply>> listEphemeral(String conversationId);

  /// Pings when the private replies of a chat may have changed.
  Stream<void> ephemeralChanges(String conversationId);

  Future<void> dismissEphemeral(String id);
}

class SupabaseInteractionsRepository implements InteractionsRepository {
  const SupabaseInteractionsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<InteractionReceipt> submit({
    required String messageId,
    required String componentId,
    Object? values,
  }) async {
    try {
      final data = await _client.rpc<Object?>(
        'submit_interaction',
        params: {
          'target_message_id': messageId,
          'target_component_id': componentId,
          'submitted_values': values,
        },
      );
      return InteractionReceipt.fromJson(
        Map<String, dynamic>.from(data! as Map),
      );
    } on PostgrestException catch (error) {
      throw InteractionException(switch (error.code) {
        'BT429' => InteractionFailure.tooFast,
        'P0002' => InteractionFailure.gone,
        '42501' => InteractionFailure.notAllowed,
        '22023' => InteractionFailure.invalid,
        _ => InteractionFailure.other,
      });
    }
  }

  @override
  Future<InteractionStatus> status(String interactionId) async {
    final data = await _client.rpc<Object?>(
      'interaction_status',
      params: {'target_interaction_id': interactionId},
    );
    return InteractionStatus.fromJson(Map<String, dynamic>.from(data! as Map));
  }

  @override
  Future<List<EphemeralReply>> listEphemeral(String conversationId) async {
    final data = await _client.rpc<Object?>(
      'list_my_ephemeral_messages',
      params: {'target_conversation_id': conversationId},
    );
    return [
      if (data is List)
        for (final row in data)
          ?EphemeralReply.maybeFromJson(
            row is Map ? Map<String, dynamic>.from(row) : null,
          ),
    ];
  }

  @override
  Stream<void> ephemeralChanges(String conversationId) {
    late RealtimeChannel channel;
    late StreamController<void> controller;
    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('ephemeral-$conversationId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'bot_ephemeral_messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'conversation_id',
                value: conversationId,
              ),
              callback: (_) {
                if (!controller.isClosed) {
                  controller.add(null);
                }
              },
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Future<void> dismissEphemeral(String id) async {
    await _client.rpc<Object?>(
      'dismiss_ephemeral_message',
      params: {'target_id': id},
    );
  }
}

/// Used where there is no server (tests).
class NoInteractionsRepository implements InteractionsRepository {
  const NoInteractionsRepository();

  @override
  Future<InteractionReceipt> submit({
    required String messageId,
    required String componentId,
    Object? values,
  }) async => throw const InteractionException(InteractionFailure.other);

  @override
  Future<InteractionStatus> status(String interactionId) async =>
      const InteractionStatus(InteractionState.pending);

  @override
  Future<List<EphemeralReply>> listEphemeral(String conversationId) async =>
      const [];

  @override
  Stream<void> ephemeralChanges(String conversationId) =>
      const Stream<void>.empty();

  @override
  Future<void> dismissEphemeral(String id) async {}
}

final interactionsRepositoryProvider = Provider<InteractionsRepository>((ref) {
  try {
    return SupabaseInteractionsRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoInteractionsRepository();
  } on Object {
    return const NoInteractionsRepository();
  }
});

/// How long a press waits for the bot before the app says the bot did not
/// answer, and how often it looks. Tests make both short.
final interactionWaitProvider = Provider<({Duration limit, Duration every})>(
  (ref) => (
    limit: const Duration(seconds: 10),
    every: const Duration(milliseconds: 1500),
  ),
);

/// The bots' private replies to me in a chat, kept up to date. Empty where
/// they cannot be read.
final ephemeralRepliesProvider = StreamProvider.autoDispose
    .family<List<EphemeralReply>, String>((ref, conversationId) async* {
      final repository = ref.watch(interactionsRepositoryProvider);
      Future<List<EphemeralReply>> load() async {
        try {
          return await repository.listEphemeral(conversationId);
        } on Object {
          return const [];
        }
      }

      yield await load();
      await for (final _ in repository.ephemeralChanges(conversationId)) {
        yield await load();
      }
    });
