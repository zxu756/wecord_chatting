/// The private Storage bucket holding soundboard clips.
const circleSoundBucket = 'circle-sounds';

/// How many sounds a circle can have.
const maxCircleSounds = 24;

/// The largest clip the server accepts.
const maxCircleSoundBytes = 512 * 1024;

/// The longest clip the server accepts; players stop there too.
const maxCircleSoundDuration = Duration(seconds: 5);

/// The longest sound name.
const maxCircleSoundNameLength = 32;

/// How long a member waits between soundboard plays.
const soundboardCooldown = Duration(seconds: 2);

/// A circle's soundboard sound (`list_circle_sounds`).
class CircleSound {
  const CircleSound({
    required this.id,
    required this.circleId,
    required this.name,
    required this.storagePath,
    required this.mimeType,
    required this.duration,
    this.emoji,
    this.createdBy,
    this.createdAt,
  });

  factory CircleSound.fromJson(Map<String, dynamic> json) {
    final emoji = (json['emoji'] as String?)?.trim();
    return CircleSound(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      name: json['name'] as String? ?? '',
      emoji: emoji == null || emoji.isEmpty ? null : emoji,
      storagePath: json['storage_path'] as String,
      mimeType: json['mime_type'] as String? ?? 'audio/mpeg',
      duration: Duration(
        milliseconds: (json['duration_ms'] as num?)?.toInt() ?? 0,
      ),
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.tryParse(
        json['created_at'] as String? ?? '',
      )?.toUtc(),
    );
  }

  final String id;
  final String circleId;
  final String name;

  /// Shown before the name; null without one.
  final String? emoji;

  /// Where the clip is in [circleSoundBucket].
  final String storagePath;
  final String mimeType;
  final Duration duration;
  final String? createdBy;
  final DateTime? createdAt;
}

/// Someone played a sound in a voice channel (a `soundboard_plays` row).
class SoundboardPlay {
  const SoundboardPlay({
    required this.channelId,
    required this.soundId,
    required this.userId,
  });

  /// Null unless [record] is a whole play.
  static SoundboardPlay? fromRecord(Map<String, dynamic> record) {
    final channelId = record['channel_id'];
    final soundId = record['sound_id'];
    final userId = record['user_id'];
    if (channelId is! String || soundId is! String || userId is! String) {
      return null;
    }
    return SoundboardPlay(
      channelId: channelId,
      soundId: soundId,
      userId: userId,
    );
  }

  final String channelId;
  final String soundId;
  final String userId;
}
