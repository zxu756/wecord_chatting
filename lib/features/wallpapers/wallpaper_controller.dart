import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/media_send/photo_compression.dart';
import 'package:wecord/features/wallpapers/wallpaper_model.dart';
import 'package:wecord/features/wallpapers/wallpaper_repository.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

/// The longer side a wallpaper photo is scaled down to before upload: a
/// full-screen phone picture, a lot less than a photo from the camera.
const wallpaperPhotoEdge = 2048;

/// JPEG quality of uploaded wallpaper photos. The picture sits behind
/// messages (often dimmed or blurred), so it is compressed harder than a
/// photo sent in a chat.
const wallpaperPhotoQuality = 80;

/// What the app knows about the person's wallpapers right now.
@immutable
class WallpaperState {
  const WallpaperState({
    this.settings = const WallpaperSettings(),
    this.loaded = false,
  });

  final WallpaperSettings settings;

  /// Whether the copy kept on this device has been read. Until then a chat
  /// does not know its wallpaper; the first paint waits for it instead of
  /// showing the plain background for a moment.
  final bool loaded;
}

/// The signed-in person's id, for keeping their wallpapers apart.
final wallpaperUserIdProvider = Provider<String?>((ref) {
  try {
    final state = ref.watch(
      authStateProvider.select(
        (state) => (hasValue: state.hasValue, id: state.value?.id),
      ),
    );
    if (state.hasValue) {
      return state.id;
    }
    return ref.read(authRepositoryProvider).currentUser?.id;
  } on Object {
    return null;
  }
});

/// The person's wallpapers: the copy on this device first, then the
/// server's, kept in step with it (also across devices, through Realtime).
final wallpapersProvider =
    NotifierProvider<WallpaperController, WallpaperState>(
      WallpaperController.new,
    );

class WallpaperController extends Notifier<WallpaperState> {
  String? _userId;
  var _revision = 0;
  Timer? _refetch;

  @override
  WallpaperState build() {
    final userId = ref.watch(wallpaperUserIdProvider);
    _userId = userId;
    _revision = 0;
    if (userId == null) {
      unawaited(_forgetPhotos());
      return const WallpaperState(loaded: true);
    }
    StreamSubscription<void>? changes;
    ref.onDispose(() {
      _refetch?.cancel();
      changes?.cancel();
    });
    unawaited(_start(userId, (subscription) => changes = subscription));
    return const WallpaperState();
  }

  Future<void> _forgetPhotos() async {
    try {
      await ref.read(wallpaperPhotoStoreProvider).clear();
    } on Object {
      // Nothing to wipe.
    }
  }

  Future<void> _start(
    String userId,
    void Function(StreamSubscription<void>) onSubscribe,
  ) async {
    WallpaperSettings? cached;
    try {
      cached = await ref.read(wallpaperSettingsStoreProvider).read(userId);
    } on Object {
      cached = null;
    }
    if (!ref.mounted || _userId != userId) {
      return;
    }
    if (_revision == 0) {
      state = WallpaperState(
        settings: cached ?? const WallpaperSettings(),
        loaded: true,
      );
    } else {
      state = WallpaperState(settings: state.settings, loaded: true);
    }
    await _fetch(userId);
    if (!ref.mounted || _userId != userId) {
      return;
    }
    try {
      onSubscribe(
        ref.read(wallpaperRepositoryProvider).changes().listen((_) {
          _refetch?.cancel();
          _refetch = Timer(
            const Duration(milliseconds: 400),
            () => unawaited(_fetch(userId)),
          );
        }, onError: (Object _) {}),
      );
    } on Object {
      // No live updates; the copy is refreshed when the app starts.
    }
  }

  Future<void> _fetch(String userId) async {
    final started = _revision;
    try {
      final remote = await ref.read(wallpaperRepositoryProvider).load();
      // A change made while loading wins over what the server said before.
      if (!ref.mounted || _userId != userId || _revision != started) {
        return;
      }
      if (remote != state.settings) {
        state = WallpaperState(settings: remote, loaded: true);
      }
      await _remember(userId, remote);
    } on Object {
      // Offline or the server lacks the feature: keep the copy.
    }
  }

  Future<void> _remember(String userId, WallpaperSettings settings) async {
    try {
      await ref.read(wallpaperSettingsStoreProvider).write(userId, settings);
    } on Object {
      // Still applies for this session.
    }
  }

  /// Refreshes from the server (the picker opens).
  Future<void> refresh() async {
    final userId = _userId;
    if (userId != null) {
      await _fetch(userId);
    }
  }

  /// Uploads a picture made by [prepareWallpaperPhoto]. Returns its path,
  /// or throws when the upload fails.
  Future<String> uploadPhoto(Uint8List prepared) async {
    final path = await ref
        .read(wallpaperRepositoryProvider)
        .uploadPhoto(prepared);
    // Shown from here without downloading it again.
    try {
      await ref.read(wallpaperPhotoStoreProvider).write(path, prepared);
    } on Object {
      // Fetched when needed.
    }
    return path;
  }

  /// Removes a photo uploaded for a wallpaper the person then dropped.
  Future<void> discardPhoto(String path) async {
    try {
      await ref.read(wallpaperRepositoryProvider).discardPhoto(path);
      await ref.read(wallpaperPhotoStoreProvider).remove(path);
    } on Object {
      // Harmless: only its owner can see it.
    }
  }

  /// Sets the wallpaper of [conversationId] (null: the default). Shows at
  /// once; put back, with the error thrown, when the server refuses.
  Future<void> set(String? conversationId, ChatWallpaper wallpaper) async {
    final userId = _userId;
    final before = state.settings;
    final oldPhoto = _photoOf(before, conversationId);
    _apply(userId, before.withWallpaper(conversationId, wallpaper));
    try {
      await ref
          .read(wallpaperRepositoryProvider)
          .save(conversationId, wallpaper);
    } on Object {
      _apply(userId, before);
      rethrow;
    }
    await _dropPhoto(oldPhoto, keeping: wallpaper.photoPath);
  }

  /// Removes the wallpaper of [conversationId] (null: the default): a chat
  /// goes back to following the default.
  Future<void> reset(String? conversationId) async {
    final userId = _userId;
    final before = state.settings;
    final oldPhoto = _photoOf(before, conversationId);
    _apply(userId, before.withWallpaper(conversationId, null));
    try {
      await ref.read(wallpaperRepositoryProvider).clear(conversationId);
    } on Object {
      _apply(userId, before);
      rethrow;
    }
    await _dropPhoto(oldPhoto);
  }

  String? _photoOf(WallpaperSettings settings, String? conversationId) {
    final current = conversationId == null
        ? settings.defaultWallpaper
        : settings.chats[conversationId];
    return current?.photoPath;
  }

  Future<void> _dropPhoto(String? path, {String? keeping}) async {
    if (path == null || path == keeping) {
      return;
    }
    try {
      await ref.read(wallpaperPhotoStoreProvider).remove(path);
    } on Object {
      // Already gone.
    }
  }

  void _apply(String? userId, WallpaperSettings settings) {
    _revision++;
    state = WallpaperState(settings: settings, loaded: true);
    if (userId != null) {
      unawaited(_remember(userId, settings));
    }
  }
}

/// The wallpaper [conversationId] shows: its own, else the default, else
/// the plain background.
final chatWallpaperProvider = Provider.family<ChatWallpaper, String>((
  ref,
  conversationId,
) {
  return ref.watch(
    wallpapersProvider.select((s) => s.settings.effective(conversationId)),
  );
});

/// Whether the copy on this device has been read.
final wallpapersLoadedProvider = Provider<bool>(
  (ref) => ref.watch(wallpapersProvider.select((s) => s.loaded)),
);

/// Makes a picture from the gallery or a file into what is uploaded as a
/// wallpaper: a JPEG scaled down to [wallpaperPhotoEdge] and compressed.
/// Throws [WallpaperPhotoException] when it cannot be read as a picture.
Future<Uint8List> prepareWallpaperPhoto(
  Uint8List bytes, {
  String fileName = 'photo',
}) async {
  final prepared = await prepareJpegPhoto(
    bytes: bytes,
    fileName: fileName,
    maxEdge: wallpaperPhotoEdge,
    quality: wallpaperPhotoQuality,
  );
  if (prepared == null) {
    throw const WallpaperPhotoException();
  }
  return prepared.bytes;
}

/// The picture could not be used as a wallpaper.
class WallpaperPhotoException implements Exception {
  const WallpaperPhotoException();

  @override
  String toString() => 'WallpaperPhotoException';
}

/// A wallpaper photo ready to draw.
@immutable
class WallpaperPhoto {
  const WallpaperPhoto({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// The photo at [path]: from this device when it is there, else downloaded
/// (and kept). Null when it cannot be had; the chat then shows the plain
/// background. Kept alive, so reopening a chat does not decode it again.
final wallpaperPhotoProvider = FutureProvider.family<WallpaperPhoto?, String>((
  ref,
  path,
) async {
  final store = ref.read(wallpaperPhotoStoreProvider);
  var bytes = await store.read(path);
  if (bytes == null) {
    try {
      bytes = await ref.read(wallpaperRepositoryProvider).downloadPhoto(path);
    } on Object {
      return null;
    }
    await store.write(path, bytes);
  }
  final size = await readPhotoSize(bytes);
  if (size == null) {
    return null;
  }
  return WallpaperPhoto(bytes: bytes, width: size.$1, height: size.$2);
});
