import 'package:flutter/foundation.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// How long the patter can take a pat back (the server allows 2 minutes).
const patUndoWindow = Duration(minutes: 2);

/// The longest pat suffix (the server enforces the same).
const patSuffixMaxLength = 20;

/// What a pat line says, read from the system message's attachment
/// `{kind: 'pat', actor_id, target_id, actor_name, target_name, suffix,
/// undone}` (migration 202610180032).
@immutable
class PatInfo {
  const PatInfo({
    required this.actorId,
    required this.targetId,
    required this.actorName,
    required this.targetName,
    this.suffix = '',
    this.undone = false,
  });

  /// Null unless [attachment] is a pat's.
  static PatInfo? maybeFromAttachment(Map<String, dynamic>? attachment) {
    if (attachment == null || attachment['kind'] != 'pat') {
      return null;
    }
    final actorId = attachment['actor_id'];
    final targetId = attachment['target_id'];
    if (actorId is! String || targetId is! String) {
      return null;
    }
    String text(String key) => (attachment[key] as String?) ?? '';
    return PatInfo(
      actorId: actorId,
      targetId: targetId,
      actorName: text('actor_name'),
      targetName: text('target_name'),
      suffix: text('suffix'),
      undone: attachment['undone'] == true,
    );
  }

  final String actorId;
  final String targetId;
  final String actorName;
  final String targetName;

  /// The patted person's suffix when it happened ("'s shoulder", "的肩膀").
  final String suffix;

  /// The patter took the pat back.
  final bool undone;
}

/// The pat a message is, or null for any other message.
PatInfo? patOf(ChatMessage message) {
  if (message.type != MessageType.system) {
    return null;
  }
  return PatInfo.maybeFromAttachment(message.attachment);
}

/// Whether [message] is a pat line (quiet: not unread, no notification).
bool isPatMessage(ChatMessage message) => patOf(message) != null;

/// [suffix] ready to follow "you": "'s shoulder" becomes "r shoulder"
/// ("patted you" + "r shoulder" = "patted your shoulder"); a Chinese "的肩膀"
/// already reads right after 你; anything else follows like after a name.
String patSuffixAfterYou(String suffix) {
  final match = RegExp(r"^['’]s(?=\s|$)").firstMatch(suffix);
  return match == null
      ? patSuffixAfterName(suffix)
      : 'r${suffix.substring(match.end)}';
}

/// [suffix] ready to follow a name: text that starts with a letter or digit
/// gets a space ("patted Ada" + " on the head"); "'s shoulder" and Chinese
/// attach directly.
String patSuffixAfterName(String suffix) {
  if (suffix.isEmpty) {
    return '';
  }
  return RegExp(r'^[A-Za-z0-9]').hasMatch(suffix) ? ' $suffix' : suffix;
}

/// The sentence of a pat line for [currentUserId]: "You patted Ada's
/// shoulder", "Bart patted you", "Bart patted Ada" (what others in a group
/// see), "You took back a pat".
String patSentence(PatInfo pat, {required String? currentUserId}) {
  final actorIsMe = currentUserId != null && pat.actorId == currentUserId;
  final targetIsMe = currentUserId != null && pat.targetId == currentUserId;
  final actor = pat.actorName.trim().isEmpty ? tr('Someone') : pat.actorName;
  final target = pat.targetName.trim().isEmpty ? tr('Someone') : pat.targetName;
  if (pat.undone) {
    return actorIsMe
        ? tr('You took back a pat')
        : tr('{name} took back a pat', {'name': actor});
  }
  if (actorIsMe) {
    return tr('You patted {name}{suffix}', {
      'name': target,
      'suffix': patSuffixAfterName(pat.suffix),
    });
  }
  if (targetIsMe) {
    return tr('{name} patted you{suffix}', {
      'name': actor,
      'suffix': patSuffixAfterYou(pat.suffix),
    });
  }
  return tr('{name} patted {target}{suffix}', {
    'name': actor,
    'target': target,
    'suffix': patSuffixAfterName(pat.suffix),
  });
}
