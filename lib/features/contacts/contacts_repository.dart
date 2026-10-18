import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/friend_request.dart';
import 'package:wecord/shared/models/profile.dart';

final contactsRepositoryProvider = Provider<ContactsRepository>((ref) {
  return SupabaseContactsRepository(ref.watch(supabaseClientProvider));
});

abstract interface class ContactsRepository {
  Future<List<Profile>> searchProfiles(String query);

  Future<List<Profile>> listFriends();

  Future<List<IncomingFriendRequest>> listIncomingRequests();

  Future<void> sendFriendRequest(String receiverId);

  Future<void> acceptFriendRequest(String requestId);

  Future<void> rejectFriendRequest(String requestId);

  Future<void> setContactAlias({
    required String friendId,
    required String? alias,
  });
}

/// Why a person cannot be sent a friend request: they chose who may send
/// one (Settings → Privacy & Safety → Adding me) and this is not you.
enum FriendRequestRefusal {
  notAccepting,
  friendsOfFriendsOnly,
  sharedCircleOnly;

  /// The refusal in a server error message, or null for any other error.
  static FriendRequestRefusal? fromServerMessage(String message) {
    if (message.contains('not accepting friend requests')) {
      return notAccepting;
    }
    if (message.contains('friends of friends')) {
      return friendsOfFriendsOnly;
    }
    if (message.contains('shared circle')) {
      return sharedCircleOnly;
    }
    return null;
  }

  String get text => switch (this) {
    notAccepting => tr('This person is not accepting friend requests.'),
    friendsOfFriendsOnly => tr(
      'This person only accepts friend requests from friends of friends.',
    ),
    sharedCircleOnly => tr(
      'This person only accepts friend requests from people in a shared circle.',
    ),
  };
}

class FriendRequestRefused implements Exception {
  const FriendRequestRefused(this.refusal);

  final FriendRequestRefusal refusal;

  @override
  String toString() => refusal.text;
}

class IncomingFriendRequest {
  const IncomingFriendRequest({required this.request, required this.requester});

  final FriendRequest request;
  final Profile requester;
}

abstract interface class ContactsDataSource {
  Future<List<Map<String, dynamic>>> searchProfiles(
    String query,
    String excludedUserId,
  );

  Future<List<Map<String, dynamic>>> listFriends(String currentUserId);

  Future<List<Map<String, dynamic>>> listIncomingRequests(String currentUserId);

  Future<List<Map<String, dynamic>>> listProfilesByIds(List<String> ids);

  Future<void> rpc(String functionName, Map<String, dynamic> params);
}

class SupabaseContactsRepository implements ContactsRepository {
  SupabaseContactsRepository(SupabaseClient client)
    : this.withDataSource(
        SupabaseContactsDataSource(client),
        currentUserId: () => client.auth.currentUser?.id,
      );

  SupabaseContactsRepository.withDataSource(
    this._dataSource, {
    required this._currentUserId,
  });

  final ContactsDataSource _dataSource;
  final String? Function() _currentUserId;

  @override
  Future<List<Profile>> searchProfiles(String query) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final currentUserId = _requireCurrentUserId();
    final rows = await _dataSource.searchProfiles(
      normalizedQuery,
      currentUserId,
    );
    return rows.map(Profile.fromJson).toList(growable: false);
  }

  @override
  Future<List<Profile>> listFriends() async {
    final currentUserId = _requireCurrentUserId();
    final rows = await _dataSource.listFriends(currentUserId);
    return rows.map(Profile.fromJson).toList(growable: false);
  }

  @override
  Future<List<IncomingFriendRequest>> listIncomingRequests() async {
    final currentUserId = _requireCurrentUserId();
    final rows = await _dataSource.listIncomingRequests(currentUserId);
    final requests = rows.map(FriendRequest.fromJson).toList(growable: false);
    final requesterIds = requests
        .map((request) => request.requesterId)
        .toSet()
        .toList(growable: false);
    if (requesterIds.isEmpty) {
      return const [];
    }

    final profileRows = await _dataSource.listProfilesByIds(requesterIds);
    final profilesById = {
      for (final profile in profileRows.map(Profile.fromJson))
        profile.id: profile,
    };

    return [
      for (final request in requests)
        if (profilesById[request.requesterId] case final requester?)
          IncomingFriendRequest(request: request, requester: requester),
    ];
  }

  @override
  Future<void> sendFriendRequest(String receiverId) async {
    _requireCurrentUserId();
    try {
      await _dataSource.rpc('send_friend_request', {
        'target_user_id': receiverId,
      });
    } on PostgrestException catch (error) {
      final refusal = FriendRequestRefusal.fromServerMessage(error.message);
      if (refusal != null) {
        throw FriendRequestRefused(refusal);
      }
      rethrow;
    }
  }

  @override
  Future<void> acceptFriendRequest(String requestId) async {
    await _dataSource.rpc('accept_friend_request', {'request_id': requestId});
  }

  @override
  Future<void> rejectFriendRequest(String requestId) async {
    await _dataSource.rpc('reject_friend_request', {'request_id': requestId});
  }

  @override
  Future<void> setContactAlias({
    required String friendId,
    required String? alias,
  }) {
    _requireCurrentUserId();
    return _dataSource.rpc('set_contact_alias', {
      'target_friend_id': friendId,
      'new_alias': alias,
    });
  }

  String _requireCurrentUserId() {
    final userId = _currentUserId();
    if (userId == null) {
      throw StateError('A signed-in user is required for contacts.');
    }
    return userId;
  }
}

class SupabaseContactsDataSource implements ContactsDataSource {
  const SupabaseContactsDataSource(this._client);

  final SupabaseClient _client;

  /// What a list of people needs. The bio, pronouns and banner can't be read
  /// from the table (they follow "who can see my profile"; the profile
  /// screen gets them from get_profile_summary), so `select *` would fail.
  static const _profileColumns =
      'id,username,display_name,avatar_url,created_at,updated_at';

  @override
  Future<List<Map<String, dynamic>>> searchProfiles(
    String query,
    String excludedUserId,
  ) async {
    // The server leaves out the caller, bots, deleted accounts, blocked
    // people and anyone who turned off "find me by username" (unless they
    // are a friend): see search_users_by_username.
    final rows = await _client.rpc<List<dynamic>>(
      'search_users_by_username',
      params: {'search_query': query},
    );
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> listFriends(String currentUserId) async {
    final rows = await _client.rpc('list_friends_with_aliases');
    return (rows as List).cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> listIncomingRequests(
    String currentUserId,
  ) async {
    final rows = await _client
        .from('friend_requests')
        .select()
        .eq('receiver_id', currentUserId)
        .eq('status', FriendRequestStatus.pending.toJson())
        .order('created_at');
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<List<Map<String, dynamic>>> listProfilesByIds(List<String> ids) async {
    if (ids.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('profiles')
        .select(_profileColumns)
        .inFilter('id', ids)
        .order('username');
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> rpc(String functionName, Map<String, dynamic> params) async {
    await _client.rpc(functionName, params: params);
  }
}
