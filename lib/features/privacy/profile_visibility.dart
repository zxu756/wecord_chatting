import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Who can see the bio, pronouns, banner and mutuals on someone's profile.
enum ProfileVisibility {
  everyone('everyone'),
  friendsAndCircles('friends_and_circles'),
  friends('friends');

  const ProfileVisibility(this.wire);

  final String wire;

  static ProfileVisibility fromWire(Object? value) {
    return values.firstWhere(
      (visibility) => visibility.wire == value,
      orElse: () => ProfileVisibility.everyone,
    );
  }

  String get label => switch (this) {
    everyone => tr('Everyone'),
    friendsAndCircles => tr('Friends and shared circles'),
    friends => tr('Friends only'),
  };

  String get description => switch (this) {
    everyone => tr('Anyone who finds your profile.'),
    friendsAndCircles => tr('Your friends and people in a circle with you.'),
    friends => tr('Only people you are friends with.'),
  };
}

abstract interface class ProfileVisibilityRepository {
  Future<ProfileVisibility> load();

  Future<void> save(ProfileVisibility visibility);
}

class SupabaseProfileVisibilityRepository
    implements ProfileVisibilityRepository {
  const SupabaseProfileVisibilityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ProfileVisibility> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return ProfileVisibility.everyone;
    }
    final row = await _client
        .from('user_privacy_settings')
        .select('profile_visibility')
        .eq('user_id', userId)
        .maybeSingle();
    return ProfileVisibility.fromWire(row?['profile_visibility']);
  }

  @override
  Future<void> save(ProfileVisibility visibility) async {
    await _client.rpc<void>(
      'set_profile_visibility',
      params: {'visibility': visibility.wire},
    );
  }
}

class _UninitializedProfileVisibilityRepository
    implements ProfileVisibilityRepository {
  const _UninitializedProfileVisibilityRepository();

  @override
  Future<ProfileVisibility> load() async => ProfileVisibility.everyone;

  @override
  Future<void> save(ProfileVisibility visibility) {
    throw StateError('Supabase must be initialized before saving privacy.');
  }
}

final profileVisibilityRepositoryProvider =
    Provider<ProfileVisibilityRepository>((ref) {
      try {
        return SupabaseProfileVisibilityRepository(
          ref.watch(supabaseClientProvider),
        );
      } on ProviderException {
        return const _UninitializedProfileVisibilityRepository();
      }
    });

/// The current user's choice (everyone until it loads, or when it cannot).
final profileVisibilityProvider =
    AsyncNotifierProvider<ProfileVisibilityController, ProfileVisibility>(
      ProfileVisibilityController.new,
    );

class ProfileVisibilityController extends AsyncNotifier<ProfileVisibility> {
  @override
  Future<ProfileVisibility> build() async {
    final userId = ref.watch(
      authStateProvider.select((state) => state.value?.id),
    );
    if (userId == null) {
      return ProfileVisibility.everyone;
    }
    try {
      return await ref.watch(profileVisibilityRepositoryProvider).load();
    } catch (_) {
      return ProfileVisibility.everyone;
    }
  }

  Future<void> set(ProfileVisibility visibility) async {
    final previous = state;
    state = AsyncData(visibility);
    try {
      await ref.read(profileVisibilityRepositoryProvider).save(visibility);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

/// Settings → Privacy & Safety → Profile visibility: the choice, with a
/// sheet to change it.
class ProfileVisibilityRow extends ConsumerWidget {
  const ProfileVisibilityRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(profileVisibilityProvider).value ??
        ProfileVisibility.everyone;
    return SettingsRow(
      key: const ValueKey('profile-visibility-row'),
      icon: Icons.badge_outlined,
      title: tr('Profile visibility'),
      subtitle: tr('Who can see your bio, pronouns, banner and mutuals'),
      value: current.label,
      onTap: () => unawaited(_choose(context, ref, current)),
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    ProfileVisibility current,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final picked = await showOptionPicker<ProfileVisibility>(
      context,
      title: tr('Profile visibility'),
      selected: current,
      note: tr(
        'Your name, picture and status stay visible to everyone. You always see your own full profile.',
      ),
      options: [
        for (final visibility in ProfileVisibility.values)
          PickerOption(
            value: visibility,
            title: visibility.label,
            subtitle: visibility.description,
          ),
      ],
    );
    if (picked == null || picked == current) {
      return;
    }
    try {
      await ref.read(profileVisibilityProvider.notifier).set(picked);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(tr('Could not save privacy settings. Try again.')),
        ),
      );
    }
  }
}
