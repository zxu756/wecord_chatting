import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/friend_tags/friend_tags_models.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// The person's private tags and stars (tables `friend_tags`,
/// `friend_tag_members` and `friend_stars`, owner-only by row level
/// security).
abstract interface class FriendTagsRepository {
  Future<FriendTagsData> load();

  /// Makes a tag; throws [FriendTagNameException] for a bad name.
  Future<FriendTag> createTag(String name);

  Future<void> renameTag(String tagId, String name);

  Future<void> deleteTag(String tagId);

  /// Puts exactly [friendIds] in the tag ([current] are the ones in it now).
  Future<void> setTagMembers(
    String tagId,
    Set<String> friendIds, {
    required Set<String> current,
  });

  Future<void> setStarred(String friendId, {required bool starred});
}

class SupabaseFriendTagsRepository implements FriendTagsRepository {
  const SupabaseFriendTagsRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('Sign in to use tags.');
    }
    return id;
  }

  @override
  Future<FriendTagsData> load() async {
    final results = await Future.wait([
      _client.from('friend_tags').select('id,name').order('created_at'),
      _client.from('friend_tag_members').select('tag_id,friend_id'),
      _client.from('friend_stars').select('friend_id'),
    ]);
    final members = <String, Set<String>>{};
    for (final row in results[1]) {
      (members[row['tag_id'] as String] ??= {}).add(row['friend_id'] as String);
    }
    return FriendTagsData(
      tags: [
        for (final row in results[0])
          FriendTag(id: row['id'] as String, name: row['name'] as String),
      ],
      members: members,
      starred: {for (final row in results[2]) row['friend_id'] as String},
    );
  }

  @override
  Future<FriendTag> createTag(String name) async {
    try {
      final row = await _client
          .from('friend_tags')
          .insert({'owner_id': _userId, 'name': name.trim()})
          .select('id,name')
          .single();
      return FriendTag(id: row['id'] as String, name: row['name'] as String);
    } on PostgrestException catch (error) {
      throw _nameProblem(error) ?? error;
    }
  }

  @override
  Future<void> renameTag(String tagId, String name) async {
    try {
      await _client
          .from('friend_tags')
          .update({'name': name.trim()})
          .eq('id', tagId);
    } on PostgrestException catch (error) {
      throw _nameProblem(error) ?? error;
    }
  }

  @override
  Future<void> deleteTag(String tagId) async {
    await _client.from('friend_tags').delete().eq('id', tagId);
  }

  @override
  Future<void> setTagMembers(
    String tagId,
    Set<String> friendIds, {
    required Set<String> current,
  }) async {
    final owner = _userId;
    final add = friendIds.difference(current);
    final remove = current.difference(friendIds);
    if (add.isNotEmpty) {
      await _client.from('friend_tag_members').insert([
        for (final id in add)
          {'tag_id': tagId, 'owner_id': owner, 'friend_id': id},
      ]);
    }
    if (remove.isNotEmpty) {
      await _client
          .from('friend_tag_members')
          .delete()
          .eq('tag_id', tagId)
          .inFilter('friend_id', remove.toList());
    }
  }

  @override
  Future<void> setStarred(String friendId, {required bool starred}) async {
    if (starred) {
      await _client
          .from('friend_stars')
          .upsert(
            {'owner_id': _userId, 'friend_id': friendId},
            onConflict: 'owner_id,friend_id',
            ignoreDuplicates: true,
          );
    } else {
      await _client.from('friend_stars').delete().eq('friend_id', friendId);
    }
  }

  FriendTagNameException? _nameProblem(PostgrestException error) {
    if (error.code == '23505') {
      return const FriendTagNameException(FriendTagNameProblem.taken);
    }
    if (error.code == '23514') {
      return const FriendTagNameException(FriendTagNameProblem.tooLong);
    }
    return null;
  }
}

/// Stands in before Supabase is set up (tests): no tags, nothing stored.
class UninitializedFriendTagsRepository implements FriendTagsRepository {
  const UninitializedFriendTagsRepository();

  @override
  Future<FriendTagsData> load() async => const FriendTagsData();

  @override
  Future<FriendTag> createTag(String name) {
    throw StateError('Supabase must be initialized to make tags.');
  }

  @override
  Future<void> renameTag(String tagId, String name) {
    throw StateError('Supabase must be initialized to change tags.');
  }

  @override
  Future<void> deleteTag(String tagId) {
    throw StateError('Supabase must be initialized to change tags.');
  }

  @override
  Future<void> setTagMembers(
    String tagId,
    Set<String> friendIds, {
    required Set<String> current,
  }) {
    throw StateError('Supabase must be initialized to change tags.');
  }

  @override
  Future<void> setStarred(String friendId, {required bool starred}) {
    throw StateError('Supabase must be initialized to star friends.');
  }
}

final friendTagsRepositoryProvider = Provider<FriendTagsRepository>((ref) {
  try {
    return SupabaseFriendTagsRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const UninitializedFriendTagsRepository();
  }
});

/// The person's tags, memberships and stars.
final friendTagsProvider = FutureProvider.autoDispose<FriendTagsData>((ref) {
  return ref.watch(friendTagsRepositoryProvider).load();
});
