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

/// Who can send the person a friend request.
enum FriendRequestFrom {
  everyone('everyone'),
  friendsOfFriends('friends_of_friends'),
  circleMembers('circle_members'),
  nobody('nobody');

  const FriendRequestFrom(this.wire);

  final String wire;

  static FriendRequestFrom fromWire(Object? value) {
    return values.firstWhere(
      (choice) => choice.wire == value,
      orElse: () => FriendRequestFrom.everyone,
    );
  }

  String get label => switch (this) {
    everyone => tr('Everyone'),
    friendsOfFriends => tr('Friends of friends'),
    circleMembers => tr('People in a shared circle'),
    nobody => tr('Nobody'),
  };

  String get description => switch (this) {
    everyone => tr('Anyone who finds you can send a request.'),
    friendsOfFriends => tr('People who have a friend in common with you.'),
    circleMembers => tr('People who are in a circle with you.'),
    nobody => tr('No one can send you a request. You can still add others.'),
  };
}

/// Who can put the person into a group without asking first.
enum GroupInviteFrom {
  allFriends('all_friends'),
  starredFriends('starred_friends'),
  approval('approval');

  const GroupInviteFrom(this.wire);

  final String wire;

  static GroupInviteFrom fromWire(Object? value) {
    return values.firstWhere(
      (choice) => choice.wire == value,
      orElse: () => GroupInviteFrom.allFriends,
    );
  }

  String get label => switch (this) {
    allFriends => tr('All friends'),
    starredFriends => tr('Starred friends'),
    approval => tr('Needs my approval'),
  };

  String get description => switch (this) {
    allFriends => tr('Any friend who runs a group can add you.'),
    starredFriends => tr(
      'Friends you starred add you directly. Others send an invitation.',
    ),
    approval => tr('You get an invitation and join when you accept.'),
  };
}

/// Who can call the person in a direct chat.
enum CallsFrom {
  friends('friends'),
  starredFriends('starred_friends'),
  nobody('nobody');

  const CallsFrom(this.wire);

  final String wire;

  static CallsFrom fromWire(Object? value) {
    return values.firstWhere(
      (choice) => choice.wire == value,
      orElse: () => CallsFrom.friends,
    );
  }

  String get label => switch (this) {
    friends => tr('Friends'),
    starredFriends => tr('Starred friends'),
    nobody => tr('Nobody'),
  };

  String get description => switch (this) {
    friends => tr('Any friend you chat with can call you.'),
    starredFriends => tr('Only friends you starred can call you.'),
    nobody => tr('No one can start a call with you in a direct chat.'),
  };
}

/// The choices of Settings → Privacy & Safety: adding me, group invitations
/// and calls. The server enforces them (migrations 202610210410 and
/// 202610210420); this is only what the person picked.
class PrivacyPermissions {
  const PrivacyPermissions({
    this.friendRequestFrom = FriendRequestFrom.everyone,
    this.discoverableByUsername = true,
    this.discoverableByQr = true,
    this.groupInviteFrom = GroupInviteFrom.allFriends,
    this.allowCallsFrom = CallsFrom.friends,
  });

  factory PrivacyPermissions.fromRow(Map<String, dynamic>? row) {
    if (row == null) {
      return const PrivacyPermissions();
    }
    return PrivacyPermissions(
      friendRequestFrom: FriendRequestFrom.fromWire(row['friend_request_from']),
      discoverableByUsername: row['discoverable_by_username'] != false,
      discoverableByQr: row['discoverable_by_qr'] != false,
      groupInviteFrom: GroupInviteFrom.fromWire(row['group_invite_from']),
      allowCallsFrom: CallsFrom.fromWire(row['allow_calls_from']),
    );
  }

  final FriendRequestFrom friendRequestFrom;
  final bool discoverableByUsername;
  final bool discoverableByQr;
  final GroupInviteFrom groupInviteFrom;
  final CallsFrom allowCallsFrom;

  PrivacyPermissions copyWith({
    FriendRequestFrom? friendRequestFrom,
    bool? discoverableByUsername,
    bool? discoverableByQr,
    GroupInviteFrom? groupInviteFrom,
    CallsFrom? allowCallsFrom,
  }) {
    return PrivacyPermissions(
      friendRequestFrom: friendRequestFrom ?? this.friendRequestFrom,
      discoverableByUsername:
          discoverableByUsername ?? this.discoverableByUsername,
      discoverableByQr: discoverableByQr ?? this.discoverableByQr,
      groupInviteFrom: groupInviteFrom ?? this.groupInviteFrom,
      allowCallsFrom: allowCallsFrom ?? this.allowCallsFrom,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrivacyPermissions &&
      other.friendRequestFrom == friendRequestFrom &&
      other.discoverableByUsername == discoverableByUsername &&
      other.discoverableByQr == discoverableByQr &&
      other.groupInviteFrom == groupInviteFrom &&
      other.allowCallsFrom == allowCallsFrom;

  @override
  int get hashCode => Object.hash(
    friendRequestFrom,
    discoverableByUsername,
    discoverableByQr,
    groupInviteFrom,
    allowCallsFrom,
  );
}

abstract interface class PrivacyPermissionsRepository {
  Future<PrivacyPermissions> load();

  /// Saves what differs between [before] and [after]; the server keeps the
  /// rest as it is.
  Future<void> save(PrivacyPermissions before, PrivacyPermissions after);
}

class SupabasePrivacyPermissionsRepository
    implements PrivacyPermissionsRepository {
  const SupabasePrivacyPermissionsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PrivacyPermissions> load() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const PrivacyPermissions();
    }
    final row = await _client
        .from('user_privacy_settings')
        .select(
          'friend_request_from,discoverable_by_username,discoverable_by_qr,'
          'group_invite_from,allow_calls_from',
        )
        .eq('user_id', userId)
        .maybeSingle();
    return PrivacyPermissions.fromRow(row);
  }

  @override
  Future<void> save(PrivacyPermissions before, PrivacyPermissions after) async {
    await _client.rpc<void>(
      'set_privacy_permissions',
      params: privacyPermissionsChanges(before, after),
    );
  }
}

/// The parameters of set_privacy_permissions: only what differs between
/// [before] and [after], so a choice made on another device is not undone.
Map<String, Object> privacyPermissionsChanges(
  PrivacyPermissions before,
  PrivacyPermissions after,
) {
  return {
    if (before.friendRequestFrom != after.friendRequestFrom)
      'friend_request_from': after.friendRequestFrom.wire,
    if (before.discoverableByUsername != after.discoverableByUsername)
      'discoverable_by_username': after.discoverableByUsername,
    if (before.discoverableByQr != after.discoverableByQr)
      'discoverable_by_qr': after.discoverableByQr,
    if (before.groupInviteFrom != after.groupInviteFrom)
      'group_invite_from': after.groupInviteFrom.wire,
    if (before.allowCallsFrom != after.allowCallsFrom)
      'allow_calls_from': after.allowCallsFrom.wire,
  };
}

class _UninitializedPrivacyPermissionsRepository
    implements PrivacyPermissionsRepository {
  const _UninitializedPrivacyPermissionsRepository();

  @override
  Future<PrivacyPermissions> load() async => const PrivacyPermissions();

  @override
  Future<void> save(PrivacyPermissions before, PrivacyPermissions after) {
    throw StateError('Supabase must be initialized before saving privacy.');
  }
}

final privacyPermissionsRepositoryProvider =
    Provider<PrivacyPermissionsRepository>((ref) {
      try {
        return SupabasePrivacyPermissionsRepository(
          ref.watch(supabaseClientProvider),
        );
      } on ProviderException {
        return const _UninitializedPrivacyPermissionsRepository();
      }
    });

/// The current user's choices (the defaults until they load, or when they
/// cannot).
final privacyPermissionsProvider =
    AsyncNotifierProvider<PrivacyPermissionsController, PrivacyPermissions>(
      PrivacyPermissionsController.new,
    );

class PrivacyPermissionsController extends AsyncNotifier<PrivacyPermissions> {
  @override
  Future<PrivacyPermissions> build() async {
    final userId = ref.watch(
      authStateProvider.select((state) => state.value?.id),
    );
    if (userId == null) {
      return const PrivacyPermissions();
    }
    try {
      return await ref.watch(privacyPermissionsRepositoryProvider).load();
    } catch (_) {
      return const PrivacyPermissions();
    }
  }

  /// Applies [change] to the choices at once and saves it; the old choices
  /// come back when saving fails.
  Future<void> change(
    PrivacyPermissions Function(PrivacyPermissions current) change,
  ) async {
    final previous = state;
    final before = previous.value ?? const PrivacyPermissions();
    final after = change(before);
    if (after == before) {
      return;
    }
    state = AsyncData(after);
    try {
      await ref.read(privacyPermissionsRepositoryProvider).save(before, after);
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

/// Settings → Privacy & Safety: "Adding me", "Group invitations" and
/// "Calls", three groups of rows.
class PrivacyPermissionsGroups extends ConsumerWidget {
  const PrivacyPermissionsGroups({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions =
        ref.watch(privacyPermissionsProvider).value ??
        const PrivacyPermissions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroup(
          header: tr('Adding me'),
          children: [
            SettingsRow(
              key: const ValueKey('friend-request-from-row'),
              icon: Icons.person_add_alt_1_outlined,
              title: tr('Who can send me friend requests'),
              value: permissions.friendRequestFrom.label,
              onTap: () => unawaited(
                _pick<FriendRequestFrom>(
                  context,
                  ref,
                  title: tr('Who can send me friend requests'),
                  current: permissions.friendRequestFrom,
                  values: FriendRequestFrom.values,
                  label: (choice) => choice.label,
                  description: (choice) => choice.description,
                  note: tr(
                    'You can still send friend requests to others yourself.',
                  ),
                  apply: (current, choice) =>
                      current.copyWith(friendRequestFrom: choice),
                ),
              ),
            ),
            SettingsRow.toggle(
              key: const ValueKey('discoverable-by-username'),
              icon: Icons.alternate_email_rounded,
              title: tr('Find me by username'),
              subtitle: tr(
                'When off, searching your username does not show you. Friends still find you.',
              ),
              value: permissions.discoverableByUsername,
              onChanged: (value) => unawaited(
                _save(
                  context,
                  ref,
                  (current) => current.copyWith(discoverableByUsername: value),
                ),
              ),
            ),
            SettingsRow.toggle(
              key: const ValueKey('discoverable-by-qr'),
              icon: Icons.qr_code_2_rounded,
              title: tr('Find me by QR code'),
              subtitle: tr(
                'When off, scanning your QR code does not lead to you. Friends still can.',
              ),
              value: permissions.discoverableByQr,
              onChanged: (value) => unawaited(
                _save(
                  context,
                  ref,
                  (current) => current.copyWith(discoverableByQr: value),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsGroup(
          header: tr('Group invitations'),
          children: [
            SettingsRow(
              key: const ValueKey('group-invite-from-row'),
              icon: Icons.group_add_outlined,
              title: tr('Who can add me to groups'),
              value: permissions.groupInviteFrom.label,
              onTap: () => unawaited(
                _pick<GroupInviteFrom>(
                  context,
                  ref,
                  title: tr('Who can add me to groups'),
                  current: permissions.groupInviteFrom,
                  values: GroupInviteFrom.values,
                  label: (choice) => choice.label,
                  description: (choice) => choice.description,
                  note: tr(
                    'Joining a group with its QR code is your own choice and always works.',
                  ),
                  apply: (current, choice) =>
                      current.copyWith(groupInviteFrom: choice),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsGroup(
          header: tr('Calls'),
          children: [
            SettingsRow(
              key: const ValueKey('calls-from-row'),
              icon: Icons.call_outlined,
              title: tr('Who can call me'),
              value: permissions.allowCallsFrom.label,
              onTap: () => unawaited(
                _pick<CallsFrom>(
                  context,
                  ref,
                  title: tr('Who can call me'),
                  current: permissions.allowCallsFrom,
                  values: CallsFrom.values,
                  label: (choice) => choice.label,
                  description: (choice) => choice.description,
                  note: tr('This is for calls in direct chats, not groups.'),
                  apply: (current, choice) =>
                      current.copyWith(allowCallsFrom: choice),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pick<T extends Enum>(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required T current,
    required List<T> values,
    required String Function(T choice) label,
    required String Function(T choice) description,
    required String note,
    required PrivacyPermissions Function(PrivacyPermissions current, T choice)
    apply,
  }) async {
    final picked = await showOptionPicker<T>(
      context,
      title: title,
      selected: current,
      note: note,
      options: [
        for (final choice in values)
          PickerOption(
            value: choice,
            title: label(choice),
            subtitle: description(choice),
          ),
      ],
    );
    if (picked == null || picked == current || !context.mounted) {
      return;
    }
    await _save(context, ref, (permissions) => apply(permissions, picked));
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    PrivacyPermissions Function(PrivacyPermissions current) change,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(privacyPermissionsProvider.notifier).change(change);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(tr('Could not save privacy settings. Try again.')),
        ),
      );
    }
  }
}
