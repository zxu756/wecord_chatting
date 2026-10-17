import 'package:flutter/foundation.dart';
import 'package:wecord/shared/models/profile.dart';

/// The longest tag name the server accepts.
const maxFriendTagNameLength = 30;

/// One of the person's private tags ("Family", "Work").
@immutable
class FriendTag {
  const FriendTag({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is FriendTag && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Everything private the person keeps about their friends: their tags, who
/// is in which, and who is starred. Only the owner can read any of it.
@immutable
class FriendTagsData {
  const FriendTagsData({
    this.tags = const [],
    this.members = const {},
    this.starred = const {},
  });

  /// The tags, in the order they were made.
  final List<FriendTag> tags;

  /// Friend ids by tag id.
  final Map<String, Set<String>> members;

  /// Starred friend ids.
  final Set<String> starred;

  Set<String> membersOf(String tagId) => members[tagId] ?? const {};

  /// The tags [friendId] is in.
  List<FriendTag> tagsOf(String friendId) => [
    for (final tag in tags)
      if (membersOf(tag.id).contains(friendId)) tag,
  ];

  bool isStarred(String friendId) => starred.contains(friendId);

  FriendTag? tagById(String id) {
    for (final tag in tags) {
      if (tag.id == id) {
        return tag;
      }
    }
    return null;
  }

  /// Starred friends first, each part in the order given.
  List<Profile> starredFirst(List<Profile> friends) => [
    ...friends.where((friend) => isStarred(friend.id)),
    ...friends.where((friend) => !isStarred(friend.id)),
  ];

  /// The friends of [friends] in the tag [tagId].
  List<Profile> inTag(List<Profile> friends, String tagId) {
    final ids = membersOf(tagId);
    return [
      for (final friend in friends)
        if (ids.contains(friend.id)) friend,
    ];
  }
}

/// What the server answers for a tag name that is empty after trimming, too
/// long or already used (ignoring case).
class FriendTagNameException implements Exception {
  const FriendTagNameException(this.reason);

  final FriendTagNameProblem reason;

  @override
  String toString() => 'FriendTagNameException($reason)';
}

enum FriendTagNameProblem { empty, tooLong, taken }

/// Checks [name] the way the server does. [existing] are the other tags
/// (without the one being renamed).
FriendTagNameProblem? checkFriendTagName(
  String name,
  Iterable<FriendTag> existing,
) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return FriendTagNameProblem.empty;
  }
  if (trimmed.length > maxFriendTagNameLength) {
    return FriendTagNameProblem.tooLong;
  }
  final lower = trimmed.toLowerCase();
  if (existing.any((tag) => tag.name.trim().toLowerCase() == lower)) {
    return FriendTagNameProblem.taken;
  }
  return null;
}
