import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/push/push_gateway.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Push isn't set up on the server (no VAPID keys yet).
class PushNotConfiguredException implements Exception {
  const PushNotConfiguredException();
}

abstract interface class PushRepository {
  /// The server's VAPID public key. Throws [PushNotConfiguredException].
  Future<String> vapidPublicKey();

  Future<void> register(PushSubscriptionInfo subscription, {String? userAgent});

  Future<void> unregister(String endpoint);

  /// Asks the server to push a message the current user just sent. Never
  /// throws: a failed push must not look like a failed send.
  Future<void> notifySent(String messageId);

  /// Rings the others for a call the current user started. Never throws.
  Future<void> notifyCall(String callId);
}

final pushRepositoryProvider = Provider<PushRepository>((ref) {
  try {
    return SupabasePushRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const NoPushRepository();
  }
});

final pushGatewayProvider = Provider<PushGateway>((ref) => createPushGateway());

class SupabasePushRepository implements PushRepository {
  const SupabasePushRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String> vapidPublicKey() async {
    try {
      final response = await _client.functions.invoke(
        'push',
        method: HttpMethod.get,
      );
      final data = response.data;
      if (data is Map && data['public_key'] is String) {
        return data['public_key'] as String;
      }
    } on FunctionException catch (error) {
      if (error.status == 503) {
        throw const PushNotConfiguredException();
      }
      rethrow;
    }
    throw const PushNotConfiguredException();
  }

  @override
  Future<void> register(
    PushSubscriptionInfo subscription, {
    String? userAgent,
  }) async {
    await _client.rpc<void>(
      'register_push_subscription',
      params: {
        'target_endpoint': subscription.endpoint,
        'target_p256dh': subscription.p256dh,
        'target_auth': subscription.auth,
        'target_user_agent': userAgent,
      },
    );
  }

  @override
  Future<void> unregister(String endpoint) async {
    await _client.rpc<void>(
      'unregister_push_subscription',
      params: {'target_endpoint': endpoint},
    );
  }

  @override
  Future<void> notifySent(String messageId) =>
      _notify({'message_id': messageId});

  @override
  Future<void> notifyCall(String callId) => _notify({'call_id': callId});

  Future<void> _notify(Map<String, String> body) async {
    try {
      await _client.functions.invoke('push', body: body);
    } catch (_) {
      // Push is a courtesy; the message is already sent.
    }
  }
}

class NoPushRepository implements PushRepository {
  const NoPushRepository();

  @override
  Future<String> vapidPublicKey() async =>
      throw const PushNotConfiguredException();

  @override
  Future<void> register(
    PushSubscriptionInfo subscription, {
    String? userAgent,
  }) async {}

  @override
  Future<void> unregister(String endpoint) async {}

  @override
  Future<void> notifySent(String messageId) async {}

  @override
  Future<void> notifyCall(String callId) async {}
}
