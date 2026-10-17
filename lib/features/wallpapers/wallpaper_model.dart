import 'package:flutter/foundation.dart';

/// What kind of picture sits behind the messages.
enum WallpaperKind {
  /// The plain background (paper). Also how one chat opts out of a default.
  none,

  /// One of the wallpapers drawn in code ([wallpaperPresets]).
  preset,

  /// The person's own photo, kept in their private storage.
  photo,
}

/// The darkest the dark-mode dim goes: a photo always gets at least this much
/// scrim so bubbles keep their contrast.
const minPhotoDim = 0.25;

/// The strongest dim the slider offers.
const maxPhotoDim = 0.65;

/// The dim a new photo wallpaper starts with.
const defaultPhotoDim = 0.4;

/// A wallpaper choice: what is behind the messages of one chat, or of every
/// chat that has none of its own. Personal: only its owner ever sees it.
@immutable
class ChatWallpaper {
  const ChatWallpaper({
    required this.kind,
    this.presetId,
    this.photoPath,
    this.dim = defaultPhotoDim,
    this.blur = false,
    this.focusX = 0,
    this.focusY = 0,
  });

  /// The plain background.
  const ChatWallpaper.none() : this(kind: WallpaperKind.none);

  /// A built-in wallpaper by id (see [wallpaperPresets]).
  const ChatWallpaper.preset(String id)
    : this(kind: WallpaperKind.preset, presetId: id);

  /// The person's photo at [path] in the `wallpapers` bucket.
  const ChatWallpaper.photo(
    String path, {
    double dim = defaultPhotoDim,
    bool blur = false,
    double focusX = 0,
    double focusY = 0,
  }) : this(
         kind: WallpaperKind.photo,
         photoPath: path,
         dim: dim,
         blur: blur,
         focusX: focusX,
         focusY: focusY,
       );

  /// A row of `chat_wallpapers` (or the same shape from the local cache).
  /// Anything unreadable is the plain background.
  factory ChatWallpaper.fromJson(Map<String, dynamic> json) {
    final kind = WallpaperKind.values.asNameMap()[json['kind']];
    double number(Object? value, double fallback) =>
        value is num && value.isFinite ? value.toDouble() : fallback;
    final path = json['photo_path'];
    final preset = json['preset_id'];
    switch (kind) {
      case WallpaperKind.preset when preset is String && preset.isNotEmpty:
        return ChatWallpaper.preset(preset);
      case WallpaperKind.photo when path is String && path.isNotEmpty:
        return ChatWallpaper.photo(
          path,
          dim: number(json['dim'], defaultPhotoDim).clamp(0.0, 1.0),
          blur: json['blur'] == true,
          focusX: number(json['focus_x'], 0).clamp(-1.0, 1.0),
          focusY: number(json['focus_y'], 0).clamp(-1.0, 1.0),
        );
      case _:
        return const ChatWallpaper.none();
    }
  }

  final WallpaperKind kind;

  /// For [WallpaperKind.preset].
  final String? presetId;

  /// For [WallpaperKind.photo]: `<user id>/<uuid>.jpg` in the bucket.
  final String? photoPath;

  /// How dark a photo gets in the dark theme, 0 to 1 (never below
  /// [minPhotoDim] when drawn).
  final double dim;

  /// Whether a photo is blurred.
  final bool blur;

  /// Where a photo sits when it is cropped to fill, -1 (left, top) to 1
  /// (right, bottom).
  final double focusX;
  final double focusY;

  bool get isNone => kind == WallpaperKind.none;
  bool get isPhoto => kind == WallpaperKind.photo && photoPath != null;
  bool get isPreset => kind == WallpaperKind.preset && presetId != null;

  ChatWallpaper copyWith({
    double? dim,
    bool? blur,
    double? focusX,
    double? focusY,
  }) {
    return ChatWallpaper(
      kind: kind,
      presetId: presetId,
      photoPath: photoPath,
      dim: dim ?? this.dim,
      blur: blur ?? this.blur,
      focusX: focusX ?? this.focusX,
      focusY: focusY ?? this.focusY,
    );
  }

  /// The row as the database and the local cache keep it.
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'preset_id': presetId,
    'photo_path': photoPath,
    'dim': dim,
    'blur': blur,
    'focus_x': focusX,
    'focus_y': focusY,
  };

  @override
  bool operator ==(Object other) =>
      other is ChatWallpaper &&
      other.kind == kind &&
      other.presetId == presetId &&
      other.photoPath == photoPath &&
      other.dim == dim &&
      other.blur == blur &&
      other.focusX == focusX &&
      other.focusY == focusY;

  @override
  int get hashCode =>
      Object.hash(kind, presetId, photoPath, dim, blur, focusX, focusY);

  @override
  String toString() => switch (kind) {
    WallpaperKind.none => 'ChatWallpaper.none',
    WallpaperKind.preset => 'ChatWallpaper.preset($presetId)',
    WallpaperKind.photo => 'ChatWallpaper.photo($photoPath)',
  };
}

/// Every wallpaper choice of one person: their default and the chats that
/// have their own.
@immutable
class WallpaperSettings {
  const WallpaperSettings({this.defaultWallpaper, this.chats = const {}});

  /// Parses rows of `chat_wallpapers` (a `conversation_id` of null is the
  /// default).
  factory WallpaperSettings.fromRows(Iterable<Map<String, dynamic>> rows) {
    ChatWallpaper? fallback;
    final chats = <String, ChatWallpaper>{};
    for (final row in rows) {
      final wallpaper = ChatWallpaper.fromJson(row);
      final conversationId = row['conversation_id'];
      if (conversationId is String) {
        chats[conversationId] = wallpaper;
      } else if (conversationId == null) {
        fallback = wallpaper;
      }
    }
    return WallpaperSettings(defaultWallpaper: fallback, chats: chats);
  }

  factory WallpaperSettings.fromJson(Map<String, dynamic> json) {
    final fallback = json['default'];
    final chats = json['chats'];
    return WallpaperSettings(
      defaultWallpaper: fallback is Map
          ? ChatWallpaper.fromJson(Map<String, dynamic>.from(fallback))
          : null,
      chats: {
        if (chats is Map)
          for (final entry in chats.entries)
            if (entry.key is String && entry.value is Map)
              entry.key as String: ChatWallpaper.fromJson(
                Map<String, dynamic>.from(entry.value as Map),
              ),
      },
    );
  }

  /// The wallpaper for chats without their own; null is the plain
  /// background.
  final ChatWallpaper? defaultWallpaper;

  /// Chats with a wallpaper of their own, by conversation id.
  final Map<String, ChatWallpaper> chats;

  /// What [conversationId] shows: its own wallpaper, else the default, else
  /// the plain background.
  ChatWallpaper effective(String conversationId) =>
      chats[conversationId] ?? defaultWallpaper ?? const ChatWallpaper.none();

  /// Whether [conversationId] has a wallpaper of its own.
  bool hasOwn(String conversationId) => chats.containsKey(conversationId);

  /// The settings with [wallpaper] for [conversationId] (null: the
  /// default). A null [wallpaper] clears that scope.
  WallpaperSettings withWallpaper(
    String? conversationId,
    ChatWallpaper? wallpaper,
  ) {
    if (conversationId == null) {
      return WallpaperSettings(defaultWallpaper: wallpaper, chats: chats);
    }
    final next = {...chats};
    if (wallpaper == null) {
      next.remove(conversationId);
    } else {
      next[conversationId] = wallpaper;
    }
    return WallpaperSettings(defaultWallpaper: defaultWallpaper, chats: next);
  }

  Map<String, dynamic> toJson() => {
    'default': defaultWallpaper?.toJson(),
    'chats': {
      for (final entry in chats.entries) entry.key: entry.value.toJson(),
    },
  };

  @override
  bool operator ==(Object other) =>
      other is WallpaperSettings &&
      other.defaultWallpaper == defaultWallpaper &&
      mapEquals(other.chats, chats);

  @override
  int get hashCode => Object.hash(
    defaultWallpaper,
    Object.hashAllUnordered([
      for (final entry in chats.entries) Object.hash(entry.key, entry.value),
    ]),
  );
}
