import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
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
    required String? Function() currentUserId,
  }) : _currentUserId = currentUserId;

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
    await _dataSource.rpc('send_friend_request', {
      'target_user_id': receiverId,
    });
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

  @override
  Future<List<Map<String, dynamic>>> searchProfiles(
    String query,
    String excludedUserId,
  ) async {
    final rows = await _client
        .from('profiles')
        .select()
        .ilike('username', '%$query%')
        .neq('id', excludedUserId)
        .order('username')
        .limit(20);
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
        .select()
        .inFilter('id', ids)
        .order('username');
    return rows.cast<Map<String, dynamic>>();
  }

  @override
  Future<void> rpc(String functionName, Map<String, dynamic> params) async {
    await _client.rpc(functionName, params: params);
  }
}
