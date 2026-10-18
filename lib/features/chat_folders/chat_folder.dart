import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wecord/shared/models/conversation.dart';

/// The most folders a person can have (the server enforces it too).
const maxChatFolders = 20;

/// The longest folder name.
const maxChatFolderNameLength = 30;

/// The kinds of chat a folder can take by itself, as the server stores them.
const chatFolderTypes = [
  ConversationType.direct,
  ConversationType.group,
  ConversationType.channel,
];

/// The icons a folder can wear, by the key the server stores.
const chatFolderIcons = <String, IconData>{
  'folder': Icons.folder_outlined,
  'work': Icons.work_outline_rounded,
  'home': Icons.home_outlined,
  'people': Icons.groups_outlined,
  'chat': Icons.chat_bubble_outline_rounded,
  'star': Icons.star_outline_rounded,
  'heart': Icons.favorite_border_rounded,
  'school': Icons.school_outlined,
  'game': Icons.sports_esports_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'travel': Icons.flight_outlined,
  'mail': Icons.mail_outline_rounded,
};

/// The icon for a stored key; the plain folder for one this app doesn't know.
IconData chatFolderIcon(String key) =>
    chatFolderIcons[key] ?? chatFolderIcons['folder']!;

/// One of the person's chat folders: rules that pick chats out of the chat
/// list. Only the rules are stored; the list is filtered on the device.
///
/// A chat is in the folder when it is not in [excludeIds] and either is in
/// [includeIds] (always, whatever the filters say) or is of a kind in
/// [includeTypes] and passes [onlyUnread], [excludeMuted] and [onlyMuted].
@immutable
class ChatFolder {
  const ChatFolder({
    required this.id,
    required this.name,
    this.icon = 'folder',
    this.sortKey = 0,
    this.includeTypes = const {},
    this.includeIds = const {},
    this.excludeIds = const {},
    this.onlyUnread = false,
    this.excludeMuted = false,
    this.onlyMuted = false,
    this.folded = false,
  });

  /// A folder that is not on the server yet.
  const ChatFolder.draft({
    required this.name,
    this.icon = 'folder',
    this.sortKey = 0,
    this.includeTypes = const {},
    this.includeIds = const {},
    this.excludeIds = const {},
    this.onlyUnread = false,
    this.excludeMuted = false,
    this.onlyMuted = false,
    this.folded = false,
  }) : id = '';

  factory ChatFolder.fromJson(Map<String, dynamic> json) {
    Set<String> strings(String key) =>
        (json[key] as List<dynamic>?)?.whereType<String>().toSet() ?? {};
    return ChatFolder(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      icon: json['icon'] as String? ?? 'folder',
      sortKey: (json['sort_key'] as num?)?.toInt() ?? 0,
      includeTypes: {
        for (final type in strings('include_types')) ?_typeOf(type),
      },
      includeIds: strings('include_ids'),
      excludeIds: strings('exclude_ids'),
      onlyUnread: json['only_unread'] as bool? ?? false,
      excludeMuted: json['exclude_muted'] as bool? ?? false,
      onlyMuted: json['only_muted'] as bool? ?? false,
      folded: json['folded'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String icon;
  final int sortKey;
  final Set<ConversationType> includeTypes;
  final Set<String> includeIds;
  final Set<String> excludeIds;
  final bool onlyUnread;
  final bool excludeMuted;
  final bool onlyMuted;

  /// Whether its chats leave the main list and show as one row.
  final bool folded;

  bool get isDraft => id.isEmpty;

  /// The columns the server stores (without the owner and the order).
  Map<String, dynamic> toRules() => {
    'name': name.trim(),
    'icon': icon,
    'include_types': [for (final type in includeTypes) type.toJson()],
    'include_ids': includeIds.toList(),
    'exclude_ids': excludeIds.toList(),
    'only_unread': onlyUnread,
    'exclude_muted': excludeMuted,
    'only_muted': onlyMuted,
    'folded': folded,
  };

  ChatFolder copyWith({
    String? name,
    String? icon,
    int? sortKey,
    Set<ConversationType>? includeTypes,
    Set<String>? includeIds,
    Set<String>? excludeIds,
    bool? onlyUnread,
    bool? excludeMuted,
    bool? onlyMuted,
    bool? folded,
  }) {
    return ChatFolder(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sortKey: sortKey ?? this.sortKey,
      includeTypes: includeTypes ?? this.includeTypes,
      includeIds: includeIds ?? this.includeIds,
      excludeIds: excludeIds ?? this.excludeIds,
      onlyUnread: onlyUnread ?? this.onlyUnread,
      excludeMuted: excludeMuted ?? this.excludeMuted,
      onlyMuted: onlyMuted ?? this.onlyMuted,
      folded: folded ?? this.folded,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatFolder &&
      other.id == id &&
      other.name == name &&
      other.icon == icon &&
      other.sortKey == sortKey &&
      setEquals(other.includeTypes, includeTypes) &&
      setEquals(other.includeIds, includeIds) &&
      setEquals(other.excludeIds, excludeIds) &&
      other.onlyUnread == onlyUnread &&
      other.excludeMuted == excludeMuted &&
      other.onlyMuted == onlyMuted &&
      other.folded == folded;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    icon,
    sortKey,
    Object.hashAllUnordered(includeTypes),
    Object.hashAllUnordered(includeIds),
    Object.hashAllUnordered(excludeIds),
    onlyUnread,
    excludeMuted,
    onlyMuted,
    folded,
  );
}

ConversationType? _typeOf(String value) {
  try {
    return ConversationType.fromJson(value);
  } catch (_) {
    return null;
  }
}

/// A starting point for a new folder, offered in the editor and on the
/// Chat folders page.
enum ChatFolderTemplate {
  unread,
  groups,
  directMessages,
  muted,
  foldedGroups;

  /// The folder this template starts from; [name] is the translated name.
  ChatFolder build(String name) {
    return switch (this) {
      ChatFolderTemplate.unread => ChatFolder.draft(
        name: name,
        icon: 'mail',
        includeTypes: chatFolderTypes.toSet(),
        onlyUnread: true,
        excludeMuted: true,
      ),
      ChatFolderTemplate.groups => ChatFolder.draft(
        name: name,
        icon: 'people',
        includeTypes: {ConversationType.group},
      ),
      ChatFolderTemplate.directMessages => ChatFolder.draft(
        name: name,
        icon: 'chat',
        includeTypes: {ConversationType.direct},
      ),
      ChatFolderTemplate.muted => ChatFolder.draft(
        name: name,
        icon: 'folder',
        includeTypes: chatFolderTypes.toSet(),
        onlyMuted: true,
      ),
      // Starts empty: the person picks which groups to fold.
      ChatFolderTemplate.foldedGroups => ChatFolder.draft(
        name: name,
        icon: 'people',
        folded: true,
      ),
    };
  }
}
