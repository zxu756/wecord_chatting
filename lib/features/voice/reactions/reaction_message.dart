import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The LiveKit data topic reactions travel on.
const reactionTopic = 'wecord.reaction';

/// The emoji a call offers. Anything else received is dropped, so the data
/// channel can't be used to put arbitrary text over someone's tile.
const callReactionEmojis = ['👍', '❤️', '😂', '😮', '👏', '🎉'];

/// An emoji someone sent in the call.
@immutable
class VoiceReaction {
  const VoiceReaction({required this.userId, required this.emoji});

  /// Who sent it: the identity LiveKit vouches for, not the message's text.
  final String userId;
  final String emoji;

  @override
  bool operator ==(Object other) =>
      other is VoiceReaction && other.userId == userId && other.emoji == emoji;

  @override
  int get hashCode => Object.hash(userId, emoji);
}

/// The data message for [emoji].
List<int> encodeReaction(String emoji) {
  return utf8.encode(jsonEncode({'v': 1, 'e': emoji}));
}

/// The emoji in a received data message, or null when it isn't a reaction
/// this app offers.
String? decodeReaction(List<int> data) {
  if (data.length > 128) {
    return null;
  }
  try {
    final decoded = jsonDecode(utf8.decode(data));
    if (decoded is! Map || decoded['v'] != 1) {
      return null;
    }
    final emoji = decoded['e'];
    return emoji is String && callReactionEmojis.contains(emoji) ? emoji : null;
  } on FormatException {
    return null;
  }
}

/// Allows at most [max] reactions in any [window]: a sender's own taps, and
/// each other person's reactions on arrival.
class ReactionRateLimiter {
  ReactionRateLimiter({
    this.max = 5,
    this.window = const Duration(seconds: 3),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int max;
  final Duration window;
  final DateTime Function() _now;
  final _times = <DateTime>[];

  /// Counts a reaction now and says whether it is within the limit; one
  /// over the limit is not counted.
  bool allow() {
    final now = _now();
    _times.removeWhere((time) => now.difference(time) >= window);
    if (_times.length >= max) {
      return false;
    }
    _times.add(now);
    return true;
  }
}

/// A [ReactionRateLimiter] per person, for what arrives.
class ReactionRateLimits {
  ReactionRateLimits({this.max = 8, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final int max;
  final DateTime Function() _now;
  final _byUser = <String, ReactionRateLimiter>{};

  bool allow(String userId) {
    return (_byUser[userId] ??= ReactionRateLimiter(
      max: max,
      now: _now,
    )).allow();
  }
}

/// Turns the data messages a room delivers into reactions: only those on
/// [reactionTopic], from a known sender, with an emoji the call offers, and
/// not too many from one person.
class ReactionReceiver {
  ReactionReceiver({DateTime Function()? now})
    : _limits = ReactionRateLimits(now: now);

  final ReactionRateLimits _limits;

  /// The reaction in a message from [senderId] on [topic], or null to drop
  /// it. [senderId] is the identity LiveKit reports (null for the server).
  VoiceReaction? receive({
    required String? senderId,
    required String? topic,
    required List<int> data,
  }) {
    if (senderId == null || topic != reactionTopic) {
      return null;
    }
    final emoji = decodeReaction(data);
    if (emoji == null || !_limits.allow(senderId)) {
      return null;
    }
    return VoiceReaction(userId: senderId, emoji: emoji);
  }
}
