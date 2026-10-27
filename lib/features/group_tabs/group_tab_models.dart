import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The kinds a tab can have today (`conversation_tab_kinds`, migration
/// 202610280540). Another package adds a kind with a row there and a
/// [GroupTabKindContribution] here; kinds the app does not know are left out
/// of the strip.
abstract final class GroupTabKinds {
  static const note = 'note';
  static const list = 'list';
  static const form = 'form';
  static const checkIn = 'check_in';
  static const link = 'link';
  static const knowledgeBase = 'kb';
  static const events = 'events';

  /// The group space (B6): registered by that package when it is merged.
  static const space = 'space';

  /// The circle's featured posts (B8): needs a circle channel, no target.
  static const featuredPosts = 'featured_posts';

  /// A whiteboard of the chat (D10); the target is the board's id.
  static const whiteboard = 'whiteboard';
}

/// The most tabs a chat can have.
const maxGroupTabs = 12;

/// One tab under the chat header.
@immutable
class GroupTab {
  const GroupTab({
    required this.id,
    required this.kind,
    required this.title,
    this.target,
    this.icon,
    this.sort = 0,
    this.available = true,
    this.closed = false,
    this.circleId,
  });

  factory GroupTab.fromJson(Map<String, dynamic> json) {
    return GroupTab(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? '',
      target: json['target'] as String?,
      title: json['title'] as String? ?? '',
      icon: json['icon'] as String?,
      sort: (json['sort'] as num?)?.toInt() ?? 0,
      available: json['available'] != false,
      closed: json['closed'] == true,
      circleId: json['circle_id'] as String?,
    );
  }

  final String id;
  final String kind;

  /// A note, list, form or check-in id, or a web address; null where the kind
  /// is the place itself.
  final String? target;

  /// The live title of the target, else the stored one.
  final String title;

  /// An emoji the target brings (a note's icon).
  final String? icon;
  final int sort;

  /// False when the target is gone or cannot be read.
  final bool available;

  /// A form or check-in that no longer takes answers.
  final bool closed;

  /// The circle of a circle channel (the knowledge base tab opens it).
  final String? circleId;
}

/// A chat's tabs and whether the caller may change them.
@immutable
class GroupTabs {
  const GroupTabs({this.tabs = const [], this.canManage = false});

  factory GroupTabs.fromJson(Map<String, dynamic> json) {
    return GroupTabs(
      canManage: json['can_manage'] == true,
      tabs: [
        for (final item in (json['tabs'] as List? ?? const []))
          if (item is Map) GroupTab.fromJson(Map<String, dynamic>.from(item)),
      ],
    );
  }

  final List<GroupTab> tabs;
  final bool canManage;
}

/// Something a tab can point at, found in the chat (a note, a list ...).
@immutable
class GroupTabCandidate {
  const GroupTabCandidate({
    required this.target,
    required this.title,
    this.icon,
    this.closed = false,
  });

  final String target;
  final String title;
  final String? icon;

  /// A form or check-in that no longer takes answers.
  final bool closed;
}

enum GroupTabFailureKind {
  limit,
  exists,
  badTarget,
  badTitle,
  notAllowed,
  gone,
  other,
}

/// A change the server refused.
class GroupTabException implements Exception {
  const GroupTabException(this.kind);

  /// Reads the server's refusal (the error texts of migration
  /// 202610280550).
  factory GroupTabException.fromPostgrest(PostgrestException error) {
    final kind = switch (error.message) {
      'tab_limit' => GroupTabFailureKind.limit,
      'tab_exists' => GroupTabFailureKind.exists,
      'tab_target_invalid' ||
      'tab_not_allowed' => GroupTabFailureKind.badTarget,
      'tab_title_invalid' => GroupTabFailureKind.badTitle,
      'Conversation not found' || 'Tab not found' => GroupTabFailureKind.gone,
      _ when error.code == '42501' => GroupTabFailureKind.notAllowed,
      _ => GroupTabFailureKind.other,
    };
    return GroupTabException(kind);
  }

  final GroupTabFailureKind kind;

  String get message => switch (kind) {
    GroupTabFailureKind.limit => tr('A chat can have up to 12 tabs.'),
    GroupTabFailureKind.exists => tr('That is already a tab.'),
    GroupTabFailureKind.badTarget => tr("That can't be a tab here."),
    GroupTabFailureKind.badTitle => tr(
      'Give the tab a name of up to 40 letters.',
    ),
    GroupTabFailureKind.notAllowed => tr('Only admins can change the tabs.'),
    GroupTabFailureKind.gone => tr("This tab isn't available any more."),
    GroupTabFailureKind.other => tr("That didn't work. Try again."),
  };

  @override
  String toString() => 'GroupTabException($kind)';
}
