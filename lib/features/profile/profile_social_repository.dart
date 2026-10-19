import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_screen.dart'
    show friendsProvider;
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/support_links.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

final profileSocialRepositoryProvider = Provider<ProfileSocialRepository>((
  ref,
) {
  return ProfileSocialRepository(
    SupabaseProfileDataSource(ref.watch(supabaseClientProvider)),
  );
});

/// Mutuals, add sources, birthdays, status audience and support links: the
/// calls of the profile extras (migrations 202610230600 to 202610230650).
class ProfileSocialRepository {
  const ProfileSocialRepository(this._dataSource);

  final ProfileDataSource _dataSource;

  /// What the profile page of [userId] shows beyond the summary.
  Future<ProfileInsights> getProfileInsights(String userId) async {
    final json = await _dataSource.rpc('get_profile_extras', {
      'target_user_id': userId,
    });
    return ProfileInsights.fromJson(json);
  }

  /// The number of mutual friends with each of [userIds] (up to 50; people
  /// the server keeps from the caller are left out).
  Future<Map<String, int>> mutualFriendCounts(List<String> userIds) async {
    if (userIds.isEmpty) {
      return const <String, int>{};
    }
    final rows = await _dataSource.rpc('get_mutual_counts', {
      'user_ids': userIds.take(50).toList(),
    });
    return {
      for (final row in (rows as List).whereType<Map<dynamic, dynamic>>())
        row['user_id'] as String: (row['friend_count'] as num).toInt(),
    };
  }

  /// Remembers where the pending request to [userId] came from. A failure is
  /// of no consequence to the person adding a friend, so it is not thrown.
  Future<void> setFriendRequestSource(
    String userId,
    FriendSource source,
  ) async {
    try {
      await _dataSource.rpc('set_friend_request_source', {
        'target_user_id': userId,
        'source': source.wire,
      });
    } on Object {
      // The request is sent; only the note of where it came from is lost.
    }
  }

  Future<MyProfileExtras> getMyExtras() async {
    final json = await _dataSource.rpc('get_my_profile_extras', const {});
    return MyProfileExtras.fromJson(json);
  }

  /// Saves my birthday; a null [birthday] removes it.
  Future<void> setMyBirthday({
    required ProfileBirthday? birthday,
    required BirthdayVisibility visibility,
    required bool reminders,
  }) async {
    await _dataSource.rpc('set_my_birthday', {
      'p_month': birthday?.month,
      'p_day': birthday?.day,
      'p_visibility': visibility.wire,
      'p_reminders': reminders,
    });
  }

  Future<void> setStatusVisibility(StatusVisibility visibility) async {
    await _dataSource.rpc('set_status_visibility', {
      'visibility': visibility.wire,
    });
  }

  /// Saves my support links (already normalized; the server checks again).
  Future<void> setMyLinks(List<SupportLink> links) async {
    await _dataSource.rpc('set_my_links', {
      'links': [for (final link in links) link.toJson()],
    });
  }

  /// The friends' statuses I may see right now.
  Future<Map<String, FriendStatus>> friendStatuses() async {
    final rows = await _dataSource.rpc('list_friend_statuses', const {});
    return {
      for (final row in (rows as List).whereType<Map<dynamic, dynamic>>())
        row['user_id'] as String: FriendStatus(
          userId: row['user_id'] as String,
          emoji: _text(row['emoji']),
          text: _text(row['status_text']),
          expiresAt: switch (row['expires_at']) {
            final String stamp => DateTime.tryParse(stamp)?.toUtc(),
            _ => null,
          },
        ),
    };
  }

  /// Friends whose birthday is on [date] in my calendar.
  Future<List<BirthdayFriend>> birthdaysOn(DateTime date) async {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final rows = await _dataSource.rpc('list_birthdays_today', {
      'on_date': '${date.year.toString().padLeft(4, '0')}-$month-$day',
    });
    return [
      for (final row in (rows as List).whereType<Map<String, dynamic>>())
        BirthdayFriend.fromJson(row),
    ];
  }

  Future<String?> circleSupportUrl(String circleId) async {
    final value = await _dataSource.rpc('get_circle_support_url', {
      'target_circle_id': circleId,
    });
    return value is String ? normalizeSupportUrl(value) : null;
  }

  /// Sets a circle's support page; blank removes it.
  Future<void> setCircleSupportUrl(String circleId, String? url) async {
    await _dataSource.rpc('set_circle_support_url', {
      'target_circle_id': circleId,
      'url': url,
    });
  }
}

String? _text(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// Notes where the pending request to [userId] came from. It never fails the
/// caller: the request is sent either way.
Future<void> recordFriendRequestSource(
  WidgetRef ref,
  String userId,
  FriendSource source,
) async {
  try {
    await ref
        .read(profileSocialRepositoryProvider)
        .setFriendRequestSource(userId, source);
  } on Object {
    // Only the note of where it came from is lost.
  }
}

/// What the profile page of a user shows beyond the summary: mutuals,
/// birthday, support links and the add source. Empty when the server cannot
/// be asked (the page still works).
final profileInsightsProvider = FutureProvider.autoDispose
    .family<ProfileInsights, String>((ref, userId) async {
      try {
        return await ref
            .watch(profileSocialRepositoryProvider)
            .getProfileInsights(userId);
      } on Object {
        return ProfileInsights.empty;
      }
    });

/// How many friends I share with each requester, for the request cards.
final mutualFriendCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, userId) async {
      try {
        final counts = await ref
            .watch(profileSocialRepositoryProvider)
            .mutualFriendCounts([userId]);
        return counts[userId] ?? 0;
      } on Object {
        return 0;
      }
    });

/// My friends' statuses by user id, for the bubbles above their avatars.
final friendStatusesProvider =
    FutureProvider.autoDispose<Map<String, FriendStatus>>((ref) async {
      // Asked again whenever the friends are (a new friend, an unfriend).
      ref.watch(friendsProvider);
      try {
        return await ref
            .watch(profileSocialRepositoryProvider)
            .friendStatuses();
      } on Object {
        return const <String, FriendStatus>{};
      }
    });

/// My own extras (birthday, status audience, links).
final myProfileExtrasProvider = FutureProvider.autoDispose<MyProfileExtras>((
  ref,
) async {
  try {
    return await ref.watch(profileSocialRepositoryProvider).getMyExtras();
  } on Object {
    return const MyProfileExtras();
  }
});

/// Friends whose birthday is today (in the device's calendar).
final birthdaysTodayProvider = FutureProvider.autoDispose<List<BirthdayFriend>>(
  (ref) async {
    try {
      return await ref
          .watch(profileSocialRepositoryProvider)
          .birthdaysOn(DateTime.now());
    } on Object {
      return const <BirthdayFriend>[];
    }
  },
);

/// A circle's support page, as its members see it.
final circleSupportUrlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, circleId) async {
      try {
        return await ref
            .watch(profileSocialRepositoryProvider)
            .circleSupportUrl(circleId);
      } on Object {
        return null;
      }
    });
