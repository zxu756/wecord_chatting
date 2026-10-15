import 'package:flutter/material.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/chats/role_mentions.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';

final _nameChar = RegExp(r'[A-Za-z0-9_]');

/// `@here` on its own, not part of an address or a longer name.
final _herePattern = RegExp(r'(?:^|[^A-Za-z0-9_@.])@here(?![A-Za-z0-9_])');

/// An `@` being typed right before the cursor, with what follows it.
final _mentionQueryPattern = RegExp(r'(?:^|\s)@([a-zA-Z0-9_]*)$');

/// The lowercased text after an `@` being typed right before the cursor of
/// [value], or null when the cursor is not in a mention.
String? mentionQueryAt(TextEditingValue value) {
  final match = _mentionMatch(value);
  return match?.group(1)?.toLowerCase();
}

RegExpMatch? _mentionMatch(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  final cursor = selection.isValid ? selection.baseOffset : text.length;
  final safeCursor = cursor.clamp(0, text.length);
  return _mentionQueryPattern.firstMatch(text.substring(0, safeCursor));
}

/// A mention candidate's name: their circle nickname in channels, otherwise
/// their display name.
String mentionName(GroupMember member) {
  final nickname = member.nickname?.trim();
  return nickname == null || nickname.isEmpty
      ? member.profile.displayName
      : nickname;
}

/// Up to [limit] of [members] whose username or name contains [query].
List<GroupMember> mentionCandidates(
  List<GroupMember> members,
  String query, {
  int limit = 6,
}) {
  return members
      .where((member) {
        return member.profile.username.toLowerCase().contains(query) ||
            mentionName(member).toLowerCase().contains(query);
      })
      .take(limit)
      .toList(growable: false);
}

/// The members picked while writing a message, turned into the message's
/// mentions when it is sent.
class MentionDraft {
  final _selections = <String, _MentionSelection>{};

  final _roles = <String, SpecialMention>{};

  /// Replaces the `@` being typed in [controller] with [member]'s username.
  /// Returns false when the cursor is not in a mention.
  bool insert(TextEditingController controller, GroupMember member) {
    if (!_replaceQuery(controller, '@${member.profile.username} ')) {
      return false;
    }
    _selections[member.profile.username] = _MentionSelection(
      userId: member.profile.id,
      username: member.profile.username,
      displayName: mentionName(member),
    );
    return true;
  }

  /// Replaces the `@` being typed in [controller] with `@here` or a role.
  bool insertSpecial(TextEditingController controller, SpecialMention special) {
    if (!_replaceQuery(controller, '${special.token} ')) {
      return false;
    }
    if (!special.isHere) {
      _roles[special.token] = special;
    }
    return true;
  }

  bool _replaceQuery(TextEditingController controller, String mentionText) {
    final text = controller.text;
    final match = _mentionMatch(controller.value);
    if (match == null) {
      return false;
    }
    final selection = controller.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final safeCursor = cursor.clamp(0, text.length);
    final prefix = text.substring(0, safeCursor);
    final tokenStart = match.start + (prefix[match.start] == '@' ? 0 : 1);
    controller.value = TextEditingValue(
      text: text.replaceRange(tokenStart, safeCursor, mentionText),
      selection: TextSelection.collapsed(
        offset: tokenStart + mentionText.length,
      ),
    );
    return true;
  }

  /// Every picked member's `@username` and picked role still in [body], in
  /// order. With [hereUserIds] (the members online now), every `@here` in
  /// [body] too, typed or picked.
  List<MessageMention> mentionsFor(String body, {List<String>? hereUserIds}) {
    final mentions = <MessageMention>[];
    for (final selection in _selections.values) {
      final token = '@${selection.username}';
      var start = body.indexOf(token);
      while (start != -1) {
        mentions.add(
          MessageMention(
            userId: selection.userId,
            displayName: selection.displayName,
            start: start,
            end: start + token.length,
          ),
        );
        start = body.indexOf(token, start + token.length);
      }
    }
    for (final role in _roles.values) {
      final token = role.token;
      var start = body.indexOf(token);
      while (start != -1) {
        final end = start + token.length;
        // Not inside a longer name: "@Mods" is not "@Moderators".
        if (end == body.length || !_nameChar.hasMatch(body[end])) {
          mentions.add(
            MessageMention.role(
              roleId: role.roleId!,
              displayName: role.name,
              color: role.color,
              start: start,
              end: end,
            ),
          );
        }
        start = body.indexOf(token, end);
      }
    }
    if (hereUserIds != null) {
      for (final match in _herePattern.allMatches(body)) {
        final start = match.start + match.group(0)!.indexOf('@');
        mentions.add(
          MessageMention.here(
            start: start,
            end: start + '@here'.length,
            userIds: hereUserIds,
          ),
        );
      }
    }
    mentions.sort((a, b) => a.start.compareTo(b.start));
    // One mention per place; the longer one wins.
    final distinct = <MessageMention>[];
    for (final mention in mentions) {
      if (distinct.isNotEmpty && mention.start < distinct.last.end) {
        if (mention.end - mention.start >
            distinct.last.end - distinct.last.start) {
          distinct.last = mention;
        }
        continue;
      }
      distinct.add(mention);
    }
    return distinct;
  }

  void clear() {
    _selections.clear();
    _roles.clear();
  }

  /// The picked members, for keeping with a draft.
  List<DraftMention> get picked => [
    for (final selection in _selections.values)
      DraftMention(
        userId: selection.userId,
        username: selection.username,
        displayName: selection.displayName,
      ),
  ];

  /// Replaces the picked members with a restored draft's.
  void restore(List<DraftMention> mentions) {
    _selections
      ..clear()
      ..addAll({
        for (final mention in mentions)
          mention.username: _MentionSelection(
            userId: mention.userId,
            username: mention.username,
            displayName: mention.displayName,
          ),
      });
  }
}

class _MentionSelection {
  const _MentionSelection({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  final String userId;
  final String username;
  final String displayName;
}

/// The @mention candidates shown above a message field.
class MentionCandidateList extends StatelessWidget {
  const MentionCandidateList({
    required this.candidates,
    required this.onSelect,
    required this.maxHeight,
    super.key,
  });

  final List<GroupMember> candidates;
  final ValueChanged<GroupMember> onSelect;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final member in candidates)
              ListTile(
                key: ValueKey('mention-candidate-${member.profile.id}'),
                dense: true,
                leading: CircleAvatar(
                  child: Text(_initials(mentionName(member))),
                ),
                title: Text(mentionName(member)),
                subtitle: Text('@${member.profile.username}'),
                onTap: () => onSelect(member),
              ),
          ],
        ),
      ),
    );
  }
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts.last.characters.first : '';
  return '$first$second'.toUpperCase();
}
