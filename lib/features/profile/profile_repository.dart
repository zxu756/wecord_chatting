import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/profile_relationship.dart';
import 'package:wecord/shared/models/report_reason.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(
    SupabaseProfileDataSource(ref.watch(supabaseClientProvider)),
  );
});

abstract interface class ProfileDataSource {
  Future<Object?> rpc(String functionName, Map<String, dynamic> params);
}

class ProfileRepository {
  const ProfileRepository(this._dataSource);

  const ProfileRepository.withDataSource(this._dataSource);

  final ProfileDataSource _dataSource;

  Future<ProfileSummary> getProfileSummary(String userId) async {
    final rows = await _dataSource.rpc('get_profile_summary', {
      'target_user_id': userId,
    });
    final list = (rows as List).cast<Map<String, dynamic>>();
    if (list.isEmpty) {
      throw StateError('Profile not found.');
    }
    return ProfileSummary.fromJson(list.single);
  }

  Future<void> blockUser(String userId) async {
    await _dataSource.rpc('block_user', {'target_user_id': userId});
  }

  Future<void> unblockUser(String userId) async {
    await _dataSource.rpc('unblock_user', {'target_user_id': userId});
  }

  Future<void> reportUser({
    required String targetUserId,
    required ReportReason reason,
    required String details,
  }) async {
    await _dataSource.rpc('report_user', {
      'target_user_id': targetUserId,
      'report_reason': reason.value,
      'report_details': details,
    });
  }
}

class SupabaseProfileDataSource implements ProfileDataSource {
  const SupabaseProfileDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) {
    return _client.rpc(functionName, params: params);
  }
}
