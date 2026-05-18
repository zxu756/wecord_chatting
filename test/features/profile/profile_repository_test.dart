import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/shared/models/report_reason.dart';

void main() {
  test('getProfileSummary calls scoped RPC and parses one row', () async {
    final dataSource = FakeProfileDataSource()
      ..rpcResult = [
        {
          'id': 'user-2',
          'username': 'ada',
          'display_name': 'Ada',
          'alias': null,
          'avatar_url': null,
          'bio': '',
          'relationship_status': 'none',
          'incoming_request_id': null,
          'outgoing_request_id': null,
          'is_blocked_by_me': false,
          'has_blocked_me': false,
        },
      ];
    final repository = ProfileRepository.withDataSource(dataSource);

    final summary = await repository.getProfileSummary('user-2');

    expect(summary.profile.username, 'ada');
    expect(dataSource.calls.single.name, 'get_profile_summary');
    expect(dataSource.calls.single.params, {'target_user_id': 'user-2'});
  });

  test('block report and unblock use narrow RPCs', () async {
    final dataSource = FakeProfileDataSource();
    final repository = ProfileRepository.withDataSource(dataSource);

    await repository.blockUser('user-2');
    await repository.reportUser(
      targetUserId: 'user-2',
      reason: ReportReason.spam,
      details: 'Repeated invites',
    );
    await repository.unblockUser('user-2');

    expect(dataSource.calls.map((call) => call.name), [
      'block_user',
      'report_user',
      'unblock_user',
    ]);
  });
}

class RpcCall {
  const RpcCall(this.name, this.params);

  final String name;
  final Map<String, dynamic> params;
}

class FakeProfileDataSource implements ProfileDataSource {
  Object? rpcResult;
  final calls = <RpcCall>[];

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    calls.add(RpcCall(functionName, params));
    return rpcResult;
  }
}
