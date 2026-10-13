import 'package:flutter/material.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';

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

  /// Replaces the `@` being typed in [controller] with [member]'s username.
  /// Returns false when the cursor is not in a mention.
  bool insert(TextEditingController controller, GroupMember member) {
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
    final mentionText = '@${member.profile.username} ';
    controller.value = TextEditingValue(
      text: text.replaceRange(tokenStart, safeCursor, mentionText),
      selection: TextSelection.collapsed(
        offset: tokenStart + mentionText.length,
      ),
    );
    _selections[member.profile.username] = _MentionSelection(
      userId: member.profile.id,
      username: member.profile.username,
      displayName: mentionName(member),
    );
    return true;
  }

  /// Every picked member's `@username` still in [body], in order.
  List<MessageMention> mentionsFor(String body) {
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
    mentions.sort((a, b) => a.start.compareTo(b.start));
    return mentions;
  }

  void clear() => _selections.clear();
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
