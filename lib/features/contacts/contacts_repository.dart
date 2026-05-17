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

  Future<List<FriendRequest>> listIncomingRequests();

  Future<void> sendFriendRequest(String receiverId);

  Future<void> acceptFriendRequest(String requestId);

  Future<void> rejectFriendRequest(String requestId);
}

abstract interface class ContactsDataSource {
  Future<List<Map<String, dynamic>>> searchProfiles(
    String query,
    String excludedUserId,
  );

  Future<List<Map<String, dynamic>>> listFriends(String currentUserId);

  Future<List<Map<String, dynamic>>> listIncomingRequests(String currentUserId);

  Future<void> insertFriendRequest(Map<String, dynamic> values);

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
  Future<List<FriendRequest>> listIncomingRequests() async {
    final currentUserId = _requireCurrentUserId();
    final rows = await _dataSource.listIncomingRequests(currentUserId);
    return rows.map(FriendRequest.fromJson).toList(growable: false);
  }

  @override
  Future<void> sendFriendRequest(String receiverId) async {
    await _dataSource.insertFriendRequest({
      'requester_id': _requireCurrentUserId(),
      'receiver_id': receiverId,
      'status': FriendRequestStatus.pending.toJson(),
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
    final friendshipRows = await _client
        .from('friendships')
        .select('user_low_id,user_high_id')
        .or('user_low_id.eq.$currentUserId,user_high_id.eq.$currentUserId');
    final friendIds = friendshipRows
        .cast<Map<String, dynamic>>()
        .map((row) {
          final lowId = row['user_low_id'] as String;
          final highId = row['user_high_id'] as String;
          return lowId == currentUserId ? highId : lowId;
        })
        .toSet()
        .toList(growable: false);

    if (friendIds.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from('profiles')
        .select()
        .inFilter('id', friendIds)
        .order('username');
    return rows.cast<Map<String, dynamic>>();
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
  Future<void> insertFriendRequest(Map<String, dynamic> values) async {
    await _client.from('friend_requests').insert(values);
  }

  @override
  Future<void> rpc(String functionName, Map<String, dynamic> params) async {
    await _client.rpc(functionName, params: params);
  }
}
