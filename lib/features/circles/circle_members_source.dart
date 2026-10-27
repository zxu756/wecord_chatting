import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/circle.dart';

/// Where the next page of a big circle's members starts: after this member in
/// the usual order (owner, admins, then by name).
class CircleMembersCursor {
  const CircleMembersCursor({
    required this.rank,
    required this.name,
    required this.userId,
  });

  final int rank;
  final String name;
  final String userId;
}

/// A page of a big circle's members.
class CircleMembersPage {
  const CircleMembersPage({required this.members, this.next});

  final List<CircleMember> members;

  /// Where the page after this one starts; null on the last page.
  final CircleMembersCursor? next;
}

/// Reads the members of a circle a page at a time, or those matching a name
/// (list_circle_members_page). A circle of thousands is never loaded whole:
/// the details hold the first page, the member list asks for the next ones
/// and searches in the database.
abstract interface class CircleMembersSource {
  Future<CircleMembersPage> page(
    String circleId, {
    CircleMembersCursor? after,
    int pageSize = 100,
  });

  /// The members whose nickname, name or username contains [query].
  Future<List<CircleMember>> search(
    String circleId,
    String query, {
    int limit = 50,
  });
}

final circleMembersSourceProvider = Provider<CircleMembersSource>((ref) {
  try {
    return SupabaseCircleMembersSource(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _NoCircleMembersSource();
  }
});

class SupabaseCircleMembersSource implements CircleMembersSource {
  const SupabaseCircleMembersSource(this._client);

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> _call(Map<String, dynamic> params) async {
    final rows = await _client.rpc<dynamic>(
      'list_circle_members_page',
      params: params,
    );
    return (rows as List<dynamic>).cast<Map<String, dynamic>>();
  }

  @override
  Future<CircleMembersPage> page(
    String circleId, {
    CircleMembersCursor? after,
    int pageSize = 100,
  }) async {
    final rows = await _call({
      'target_circle_id': circleId,
      'page_size': pageSize,
      'after_rank': after?.rank,
      'after_name': after?.name,
      'after_user_id': after?.userId,
    });
    final members = rows.map(CircleMember.fromJson).toList(growable: false);
    CircleMembersCursor? next;
    if (rows.length >= pageSize && rows.isNotEmpty) {
      final last = rows.last;
      next = CircleMembersCursor(
        rank: (last['sort_rank'] as num).toInt(),
        name: last['sort_name'] as String? ?? '',
        userId: (last['profile'] as Map<String, dynamic>)['id'] as String,
      );
    }
    return CircleMembersPage(members: members, next: next);
  }

  @override
  Future<List<CircleMember>> search(
    String circleId,
    String query, {
    int limit = 50,
  }) async {
    final rows = await _call({
      'target_circle_id': circleId,
      'page_size': limit,
      'search_text': query,
    });
    return rows.map(CircleMember.fromJson).toList(growable: false);
  }
}

class _NoCircleMembersSource implements CircleMembersSource {
  const _NoCircleMembersSource();

  @override
  Future<CircleMembersPage> page(
    String circleId, {
    CircleMembersCursor? after,
    int pageSize = 100,
  }) async => const CircleMembersPage(members: []);

  @override
  Future<List<CircleMember>> search(
    String circleId,
    String query, {
    int limit = 50,
  }) async => const [];
}
