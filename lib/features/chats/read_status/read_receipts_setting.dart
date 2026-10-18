import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The person's choice to tell others when they have read their messages
/// (`user_privacy_settings.send_read_receipts`, migration 202610220300).
abstract interface class ReadReceiptsRepository {
  Future<bool> load();

  Future<void> save(bool enabled);
}

class SupabaseReadReceiptsRepository implements ReadReceiptsRepository {
  const SupabaseReadReceiptsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return true;
    }
    final row = await _client
        .from('user_privacy_settings')
        .select('send_read_receipts')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['send_read_receipts'] != false;
  }

  @override
  Future<void> save(bool enabled) async {
    await _client.rpc<bool>(
      'set_send_read_receipts',
      params: {'enabled': enabled},
    );
  }
}

class _UninitializedReadReceiptsRepository implements ReadReceiptsRepository {
  const _UninitializedReadReceiptsRepository();

  @override
  Future<bool> load() async => true;

  @override
  Future<void> save(bool enabled) {
    throw StateError('Supabase must be initialized before saving privacy.');
  }
}

final readReceiptsRepositoryProvider = Provider<ReadReceiptsRepository>((ref) {
  try {
    return SupabaseReadReceiptsRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedReadReceiptsRepository();
  }
});

/// Whether the current user sends read receipts (on until it loads, or when
/// it cannot).
final sendReadReceiptsProvider =
    AsyncNotifierProvider<SendReadReceiptsController, bool>(
      SendReadReceiptsController.new,
    );

class SendReadReceiptsController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final userId = ref.watch(
      authStateProvider.select((state) => state.value?.id),
    );
    if (userId == null) {
      return true;
    }
    try {
      return await ref.watch(readReceiptsRepositoryProvider).load();
    } catch (_) {
      return true;
    }
  }

  /// Shows [enabled] at once and saves it; the old choice comes back when
  /// saving fails.
  Future<void> set(bool enabled) async {
    final previous = state;
    state = AsyncData(enabled);
    try {
      await ref.read(readReceiptsRepositoryProvider).save(enabled);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

/// Settings → Privacy & Safety → Send read receipts: a switch.
class ReadReceiptsRow extends ConsumerWidget {
  const ReadReceiptsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(sendReadReceiptsProvider).value ?? true;
    return SettingsRow.toggle(
      key: const ValueKey('read-receipts-row'),
      icon: Icons.done_all_rounded,
      title: tr('Send read receipts'),
      subtitle: tr(
        'When off, others see you as unknown in read lists, and you do not see their read receipts either.',
      ),
      value: enabled,
      onChanged: (value) => unawaited(_save(context, ref, value)),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref, bool value) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(sendReadReceiptsProvider.notifier).set(value);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(tr('Could not save privacy settings. Try again.')),
        ),
      );
    }
  }
}
