import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/local_data/local_cipher_provider.dart';
import 'package:wecord/features/wallpapers/wallpaper_store.dart';

/// The shared-preferences keys that hold what was said or read in chats
/// (texts read from pictures, transcripts, video captions, unsent drafts,
/// what was searched for).
bool isChatContentPreferenceKey(String key) {
  return key.startsWith('wecord.transcripts.') ||
      key.startsWith('wecord.image_text.') ||
      key.startsWith('wecord.video_captions.') ||
      key.startsWith('wecord.search.recent') ||
      (key.startsWith('wecord.chats.') && key.endsWith('.drafts'));
}

/// Forgets what the device kept of the chats of whoever signed out (G8),
/// beyond the offline cache itself: the texts read from pictures and voice
/// messages, captions, drafts, recent searches and the cached wallpaper
/// photos, and then the key everything was encrypted with. Whatever this
/// misses can no longer be read: with the key gone it is only noise.
///
/// The key is kept if somebody has signed in again in the meantime (it is
/// theirs now).
Future<void> wipeLocalChatData(Ref ref) async {
  try {
    final preferences = await SharedPreferences.getInstance();
    for (final key in preferences.getKeys().toList()) {
      if (isChatContentPreferenceKey(key)) {
        await preferences.remove(key);
      }
    }
  } on Object {
    // Nothing kept, or storage is gone.
  }
  try {
    await ref.read(wallpaperPhotoStoreProvider).clear();
  } on Object {
    // Nothing kept.
  }
  try {
    if (ref.read(authRepositoryProvider).currentUser == null) {
      await ref.read(localCipherProvider).destroyKey();
    }
  } on Object {
    // The key could not be removed; the data it protected is gone anyway.
  }
}
