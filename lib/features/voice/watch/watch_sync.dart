/// How far apart a listener may drift from the host before being moved. The
/// roadmap's number: more than a second is noticeable in a conversation.
const watchDriftLimit = Duration(seconds: 1);

/// After moving a player, give it this long to settle (seeking and buffering
/// take a moment) before judging it again.
const watchSettleTime = Duration(seconds: 3);

/// Where the playback should be at [now], given that it was at [anchor] at
/// [anchorAt] and is [playing]. Never negative, and never past [duration]
/// when it is known.
Duration expectedWatchPosition({
  required Duration anchor,
  required DateTime anchorAt,
  required DateTime now,
  required bool playing,
  Duration? duration,
}) {
  var position = anchor;
  if (playing) {
    final elapsed = now.difference(anchorAt);
    if (!elapsed.isNegative) {
      position += elapsed;
    }
  }
  if (duration != null && position > duration) {
    position = duration;
  }
  return position;
}

/// What to do about a player that is at [actual] when it should be at
/// [expected]: the position to move it to, or null when it is close enough.
/// A paused player is moved at once when it differs at all by more than a
/// fraction of a second (nothing is moving, so there is no drift to forgive).
Duration? watchCorrection({
  required Duration expected,
  required Duration actual,
  required bool playing,
  Duration limit = watchDriftLimit,
}) {
  final drift = (actual - expected).abs();
  final allowed = playing ? limit : const Duration(milliseconds: 400);
  return drift > allowed ? expected : null;
}

/// Remembers when a player was last moved so it is not moved again before
/// it settles.
class WatchSettleGate {
  DateTime? _movedAt;

  void moved(DateTime now) => _movedAt = now;

  bool isSettled(DateTime now, {Duration time = watchSettleTime}) {
    final movedAt = _movedAt;
    return movedAt == null || now.difference(movedAt) >= time;
  }

  void clear() => _movedAt = null;
}
