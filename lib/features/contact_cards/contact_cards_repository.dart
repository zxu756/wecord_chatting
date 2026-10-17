import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/contact_cards/contact_card_models.dart';
import 'package:wecord/features/push/push_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The server will not share this person or circle: they hid their profile
/// from the sender, one blocked the other, or the sender may not create
/// invites for the circle.
class ContactCardRefusedException implements Exception {
  const ContactCardRefusedException();

  @override
  String toString() => tr('This contact cannot be shared.');
}

abstract interface class ContactCardsRepository {
  /// Sends a card of the person or circle [targetId] to [conversationId];
  /// returns the new message's id.
  Future<String> send({
    required String conversationId,
    required ContactCardKind kind,
    required String targetId,
  });
}

final contactCardsRepositoryProvider = Provider<ContactCardsRepository>((ref) {
  try {
    return SupabaseContactCardsRepository(
      ref.watch(supabaseClientProvider),
      onSent: ref.watch(pushRepositoryProvider).notifySent,
    );
  } on ProviderException {
    return const UninitializedContactCardsRepository();
  }
});

class SupabaseContactCardsRepository implements ContactCardsRepository {
  const SupabaseContactCardsRepository(this._client, {this.onSent});

  final SupabaseClient _client;
  final Future<void> Function(String messageId)? onSent;

  @override
  Future<String> send({
    required String conversationId,
    required ContactCardKind kind,
    required String targetId,
  }) async {
    final Object? created;
    try {
      created = await _client.rpc<Object?>(
        'send_contact_card',
        params: {
          'target_conversation_id': conversationId,
          'card_kind': kind.name,
          'card_target_id': targetId,
        },
      );
    } on PostgrestException catch (error) {
      final refused = SendRefusedException.fromPostgrest(error);
      if (refused != null) {
        throw refused;
      }
      if (error.code == '42501' && error.message.contains('cannot be shared')) {
        throw const ContactCardRefusedException();
      }
      rethrow;
    }
    if (created is! String) {
      throw const AutoModBlockedException();
    }
    await onSent?.call(created);
    return created;
  }
}

class UninitializedContactCardsRepository implements ContactCardsRepository {
  const UninitializedContactCardsRepository();

  @override
  Future<String> send({
    required String conversationId,
    required ContactCardKind kind,
    required String targetId,
  }) => throw StateError('Supabase is not initialized');
}
