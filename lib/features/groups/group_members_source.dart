import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/group.dart';

/// A page of a big group's members.
class GroupMembersPage {
  const GroupMembersPage({required this.members, this.next});

  final List<GroupMember> members;

  /// Where the page after this one starts; null on the last page (and on a
  /// search, which is one page of the best matches).
  final GroupMembersCursor? next;
}

/// Reads the members of a group a page at a time, or those matching a name
/// (list_conversation_members_page). A group of thousands is never loaded
/// whole: the sheet shows a page, "show more" asks for the next, a search
/// asks the database, and so does the @-mention picker.
abstract interface class GroupMembersSource {
  Future<GroupMembersPage> page(
    String conversationId, {
    GroupMembersCursor? after,
    int pageSize = 100,
  });

  /// The members whose name, username, alias or circle nickname contains
  /// [query], at most [limit] of them.
  Future<List<GroupMember>> search(
    String conversationId,
    String query, {
    int limit = 30,
  });
}

final groupMembersSourceProvider = Provider<GroupMembersSource>((ref) {
  try {
    return SupabaseGroupMembersSource(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _NoGroupMembersSource();
  }
});

class SupabaseGroupMembersSource implements GroupMembersSource {
  const SupabaseGroupMembersSource(this._client);

  final SupabaseClient _client;

  Future<List<GroupMember>> _call(Map<String, dynamic> params) async {
    final rows = await _client.rpc<dynamic>(
      'list_conversation_members_page',
      params: params,
    );
    return (rows as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(GroupMember.fromJson)
        .toList(growable: false);
  }

  @override
  Future<GroupMembersPage> page(
    String conversationId, {
    GroupMembersCursor? after,
    int pageSize = 100,
  }) async {
    final members = await _call({
      'target_conversation_id': conversationId,
      'page_size': pageSize,
      'after_joined_at': after?.joinedAt.toUtc().toIso8601String(),
      'after_user_id': after?.userId,
    });
    return GroupMembersPage(
      members: members,
      next: members.length >= pageSize
          ? GroupMembersCursor.after(members.last)
          : null,
    );
  }

  @override
  Future<List<GroupMember>> search(
    String conversationId,
    String query, {
    int limit = 30,
  }) {
    return _call({
      'target_conversation_id': conversationId,
      'page_size': limit,
      'search_text': query,
    });
  }
}

class _NoGroupMembersSource implements GroupMembersSource {
  const _NoGroupMembersSource();

  @override
  Future<GroupMembersPage> page(
    String conversationId, {
    GroupMembersCursor? after,
    int pageSize = 100,
  }) async => const GroupMembersPage(members: []);

  @override
  Future<List<GroupMember>> search(
    String conversationId,
    String query, {
    int limit = 30,
  }) async => const [];
}
