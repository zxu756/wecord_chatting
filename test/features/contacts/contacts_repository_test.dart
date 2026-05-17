import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/shared/models/friend_request.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  test(
    'searchProfiles trims, lowercases, and excludes the current user',
    () async {
      final dataSource = FakeContactsDataSource();
      final repository = SupabaseContactsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'current-user',
      );

      await repository.searchProfiles('  ADA  ');

      expect(dataSource.searchCalls, [
        const SearchCall(query: 'ada', excludedUserId: 'current-user'),
      ]);
    },
  );

  test('searchProfiles returns empty results for blank queries', () async {
    final dataSource = FakeContactsDataSource();
    final repository = SupabaseContactsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'current-user',
    );

    final results = await repository.searchProfiles('   ');

    expect(results, isEmpty);
    expect(dataSource.searchCalls, isEmpty);
  });

  test('listFriends parses profile rows returned by the data source', () async {
    final dataSource = FakeContactsDataSource()
      ..friendsRows = [_profileRow(id: 'friend-1', username: 'grace')];
    final repository = SupabaseContactsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'current-user',
    );

    final friends = await repository.listFriends();

    expect(friends, hasLength(1));
    expect(friends.single, isA<Profile>());
    expect(friends.single.id, 'friend-1');
    expect(dataSource.friendsCalls, ['current-user']);
  });

  test(
    'listIncomingRequests fetches pending requests for the current user',
    () async {
      final dataSource = FakeContactsDataSource()
        ..incomingRows = [
          _requestRow(
            id: 'request-1',
            requesterId: 'friend-1',
            receiverId: 'current-user',
          ),
        ];
      final repository = SupabaseContactsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'current-user',
      );

      final requests = await repository.listIncomingRequests();

      expect(requests, hasLength(1));
      expect(requests.single, isA<FriendRequest>());
      expect(requests.single.id, 'request-1');
      expect(dataSource.incomingCalls, ['current-user']);
    },
  );

  test(
    'sendFriendRequest inserts a pending request from the current user',
    () async {
      final dataSource = FakeContactsDataSource();
      final repository = SupabaseContactsRepository.withDataSource(
        dataSource,
        currentUserId: () => 'current-user',
      );

      await repository.sendFriendRequest('friend-1');

      expect(dataSource.inserts, [
        {
          'requester_id': 'current-user',
          'receiver_id': 'friend-1',
          'status': 'pending',
        },
      ]);
    },
  );

  test('accept and reject friend requests call hardened RPCs', () async {
    final dataSource = FakeContactsDataSource();
    final repository = SupabaseContactsRepository.withDataSource(
      dataSource,
      currentUserId: () => 'current-user',
    );

    await repository.acceptFriendRequest('request-1');
    await repository.rejectFriendRequest('request-2');

    expect(dataSource.rpcCalls, [
      const RpcCall(
        functionName: 'accept_friend_request',
        params: {'request_id': 'request-1'},
      ),
      const RpcCall(
        functionName: 'reject_friend_request',
        params: {'request_id': 'request-2'},
      ),
    ]);
  });
}

class FakeContactsDataSource implements ContactsDataSource {
  var profileRows = <Map<String, dynamic>>[];
  var friendsRows = <Map<String, dynamic>>[];
  var incomingRows = <Map<String, dynamic>>[];
  final searchCalls = <SearchCall>[];
  final friendsCalls = <String>[];
  final incomingCalls = <String>[];
  final inserts = <Map<String, dynamic>>[];
  final rpcCalls = <RpcCall>[];

  @override
  Future<List<Map<String, dynamic>>> searchProfiles(
    String query,
    String excludedUserId,
  ) async {
    searchCalls.add(SearchCall(query: query, excludedUserId: excludedUserId));
    return profileRows;
  }

  @override
  Future<List<Map<String, dynamic>>> listFriends(String currentUserId) async {
    friendsCalls.add(currentUserId);
    return friendsRows;
  }

  @override
  Future<List<Map<String, dynamic>>> listIncomingRequests(
    String currentUserId,
  ) async {
    incomingCalls.add(currentUserId);
    return incomingRows;
  }

  @override
  Future<void> insertFriendRequest(Map<String, dynamic> values) async {
    inserts.add(values);
  }

  @override
  Future<void> rpc(String functionName, Map<String, dynamic> params) async {
    rpcCalls.add(RpcCall(functionName: functionName, params: params));
  }
}

class SearchCall {
  const SearchCall({required this.query, required this.excludedUserId});

  final String query;
  final String excludedUserId;

  @override
  bool operator ==(Object other) {
    return other is SearchCall &&
        other.query == query &&
        other.excludedUserId == excludedUserId;
  }

  @override
  int get hashCode => Object.hash(query, excludedUserId);
}

class RpcCall {
  const RpcCall({required this.functionName, required this.params});

  final String functionName;
  final Map<String, dynamic> params;

  @override
  bool operator ==(Object other) {
    return other is RpcCall &&
        other.functionName == functionName &&
        _mapsEqual(other.params, params);
  }

  @override
  int get hashCode => Object.hash(functionName, Object.hashAll(params.entries));
}

bool _mapsEqual(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

Map<String, dynamic> _profileRow({
  required String id,
  required String username,
}) {
  return {
    'id': id,
    'username': username,
    'display_name': username,
    'avatar_url': null,
    'bio': '',
    'created_at': '2026-05-18T00:00:00.000Z',
    'updated_at': '2026-05-18T00:00:00.000Z',
  };
}

Map<String, dynamic> _requestRow({
  required String id,
  required String requesterId,
  required String receiverId,
}) {
  return {
    'id': id,
    'requester_id': requesterId,
    'receiver_id': receiverId,
    'status': 'pending',
    'created_at': '2026-05-18T00:00:00.000Z',
    'updated_at': '2026-05-18T00:00:00.000Z',
  };
}
