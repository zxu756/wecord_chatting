import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/chat_lock_repository.dart';
import 'package:wecord/features/app_lock/lock_secret.dart';
import 'package:wecord/features/app_lock/lock_storage.dart';
import 'package:wecord/features/auth/auth_repository.dart';

const _idsKey = 'chat_ids';
const _hideKey = 'chat_hide';
const _secretKey = 'chat_secret';

/// How long a chat that was opened with the lock stays open after the person
/// leaves it (so going back and forth between a locked chat and its profile
/// does not ask again and again).
const chatUnlockGrace = Duration(minutes: 1);

/// The longest secret code, and the shortest.
const secretCodeMinLength = 4;
const secretCodeMaxLength = 20;

/// What the chat lock knows right now.
@immutable
class ChatLockState {
  const ChatLockState({
    this.lockedIds = const {},
    this.hideLocked = false,
    this.hasSecretCode = false,
    this.revealed = false,
    this.unlockedIds = const {},
  });

  /// The chats the person locked (from the server, kept on the device too).
  final Set<String> lockedIds;

  /// Locked chats are left out of the lists until the secret code is typed.
  final bool hideLocked;
  final bool hasSecretCode;

  /// The secret code was typed since the app was last out of sight: hidden
  /// chats show in the lists.
  final bool revealed;

  /// Locked chats opened with the lock since the app was last out of sight.
  final Set<String> unlockedIds;

  /// The chats the lists leave out.
  Set<String> get hiddenIds =>
      hideLocked && !revealed ? lockedIds : const <String>{};

  ChatLockState copyWith({
    Set<String>? lockedIds,
    bool? hideLocked,
    bool? hasSecretCode,
    bool? revealed,
    Set<String>? unlockedIds,
  }) {
    return ChatLockState(
      lockedIds: lockedIds ?? this.lockedIds,
      hideLocked: hideLocked ?? this.hideLocked,
      hasSecretCode: hasSecretCode ?? this.hasSecretCode,
      revealed: revealed ?? this.revealed,
      unlockedIds: unlockedIds ?? this.unlockedIds,
    );
  }
}

/// Chat lock: some chats ask for Face ID, Touch ID, the passcode or the PIN
/// to open, show no preview in the lists and no text in notifications, and
/// can be hidden from the lists until a secret code is typed in the search.
///
/// Which chats are locked is kept on the server (see [ChatLockRepository]);
/// the rest stays on this device.
final chatLockProvider = NotifierProvider<ChatLockController, ChatLockState>(
  ChatLockController.new,
);

/// The ids of the locked chats. Changes only when the list does.
final lockedConversationIdsProvider = Provider<Set<String>>(
  (ref) => ref.watch(chatLockProvider.select((state) => state.lockedIds)),
);

/// The ids of the chats the lists leave out.
final hiddenConversationIdsProvider = Provider<Set<String>>(
  (ref) => ref.watch(chatLockProvider.select((state) => state.hiddenIds)),
);

class ChatLockController extends Notifier<ChatLockState> {
  StoredSecret? _secret;
  final _leftAt = <String, DateTime>{};

  LockStorage get _storage => ref.read(lockStorageProvider);

  @override
  ChatLockState build() {
    final storage = ref.read(lockStorageProvider);
    _secret = StoredSecret.decode(storage.read(_secretKey));
    ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (previous, next) {
      final hadUser = previous?.value != null;
      if (hadUser && next.hasValue && next.value?.id != previous?.value?.id) {
        // Someone else signed in (or nobody did): start from their own list.
        unawaited(wipe().then((_) => next.value == null ? null : refresh()));
      } else if (next.value != null && next.value?.id != previous?.value?.id) {
        unawaited(refresh());
      }
    });
    // The server's list replaces the one kept here as soon as it answers.
    Future<void>.microtask(refresh);
    return ChatLockState(
      lockedIds: _readIds(storage),
      hideLocked: storage.read(_hideKey) == '1',
      hasSecretCode: _secret != null,
    );
  }

  static Set<String> _readIds(LockStorage storage) {
    try {
      final decoded = jsonDecode(storage.read(_idsKey) ?? '[]');
      return decoded is List ? {...decoded.whereType<String>()} : const {};
    } on Object {
      return const {};
    }
  }

  Future<void> _keepIds(Set<String> ids) => _storage.write(
    _idsKey,
    ids.isEmpty ? null : jsonEncode(ids.toList()..sort()),
  );

  /// Asks the server which chats are locked. A failure keeps what is known.
  Future<void> refresh() async {
    if (ref.read(authRepositoryProviderOrNull)?.currentUser == null) {
      return;
    }
    try {
      final ids = await ref.read(chatLockRepositoryProvider).load();
      if (!ref.mounted || setEquals(ids, state.lockedIds)) {
        return;
      }
      state = state.copyWith(
        lockedIds: ids,
        unlockedIds: {...state.unlockedIds}..retainAll(ids),
      );
      await _keepIds(ids);
    } on Object {
      // Offline: the list kept on the device stands.
    }
  }

  /// Locks [conversationId]. Throws when the server cannot be reached: a
  /// lock that only this device knows about would not hide the pushes.
  Future<void> lock(String conversationId) async {
    if (state.lockedIds.contains(conversationId)) {
      return;
    }
    await ref
        .read(chatLockRepositoryProvider)
        .setLocked(conversationId, locked: true);
    final ids = {...state.lockedIds, conversationId};
    // The person has just proved who they are: the chat stays open.
    state = state.copyWith(
      lockedIds: ids,
      unlockedIds: {...state.unlockedIds, conversationId},
    );
    await _keepIds(ids);
  }

  /// Takes the lock off [conversationId]. The caller has asked the person to
  /// prove it is them.
  Future<void> unlock(String conversationId) async {
    if (!state.lockedIds.contains(conversationId)) {
      return;
    }
    await ref
        .read(chatLockRepositoryProvider)
        .setLocked(conversationId, locked: false);
    final ids = {...state.lockedIds}..remove(conversationId);
    state = state.copyWith(
      lockedIds: ids,
      unlockedIds: {...state.unlockedIds}..remove(conversationId),
    );
    _leftAt.remove(conversationId);
    await _keepIds(ids);
  }

  // ------------------------------------------------------- open sessions

  /// Whether [conversationId] was opened with the lock and is still open: it
  /// is on screen, or was left less than [chatUnlockGrace] ago.
  bool isOpen(String conversationId, {DateTime? now}) {
    if (!state.lockedIds.contains(conversationId)) {
      return true;
    }
    if (!state.unlockedIds.contains(conversationId)) {
      return false;
    }
    final left = _leftAt[conversationId];
    return left == null ||
        (now ?? ref.read(lockClockProvider)()).difference(left) <
            chatUnlockGrace;
  }

  /// The person proved who they are: [conversationId] opens.
  void markOpened(String conversationId) {
    _leftAt.remove(conversationId);
    if (!state.unlockedIds.contains(conversationId)) {
      state = state.copyWith(
        unlockedIds: {...state.unlockedIds, conversationId},
      );
    }
  }

  /// The chat left the screen: it stays open for the grace period.
  void markLeft(String conversationId) {
    if (state.unlockedIds.contains(conversationId)) {
      _leftAt[conversationId] = ref.read(lockClockProvider)();
    }
  }

  /// Makes [conversationId] ask again.
  void relock(String conversationId) {
    _leftAt.remove(conversationId);
    if (state.unlockedIds.contains(conversationId)) {
      state = state.copyWith(
        unlockedIds: {...state.unlockedIds}..remove(conversationId),
      );
    }
  }

  /// The app was out of sight: every chat asks again, and hidden chats hide
  /// again.
  void relockAll() {
    _leftAt.clear();
    if (state.unlockedIds.isNotEmpty || state.revealed) {
      state = state.copyWith(unlockedIds: const {}, revealed: false);
    }
  }

  // ----------------------------------------------------- hiding, the code

  Future<void> setHideLocked(bool hide) async {
    await _storage.write(_hideKey, hide ? '1' : null);
    state = state.copyWith(hideLocked: hide, revealed: false);
  }

  Future<void> setSecretCode(String code) async {
    final secret = StoredSecret.of(_normalise(code));
    _secret = secret;
    await _storage.write(_secretKey, secret.encode());
    state = state.copyWith(hasSecretCode: true);
  }

  Future<void> clearSecretCode() async {
    _secret = null;
    await _storage.write(_secretKey, null);
    state = state.copyWith(hasSecretCode: false, revealed: false);
  }

  /// If [typed] (what is in a search box) is the secret code, shows the
  /// hidden chats in the lists and answers true.
  bool tryReveal(String typed) {
    final secret = _secret;
    if (secret == null || !state.hideLocked) {
      return false;
    }
    final candidate = _normalise(typed);
    if (candidate.length < secretCodeMinLength ||
        candidate.length > secretCodeMaxLength) {
      return false;
    }
    if (!secret.accepts(candidate)) {
      return false;
    }
    if (!state.revealed) {
      state = state.copyWith(revealed: true);
    }
    return true;
  }

  /// Hides the chats again without leaving the app.
  void hideAgain() {
    if (state.revealed) {
      state = state.copyWith(revealed: false);
    }
  }

  static String _normalise(String code) => code.trim().toLowerCase();

  /// Forgets everything kept on this device (signing out).
  Future<void> wipe() async {
    _secret = null;
    _leftAt.clear();
    for (final key in [_idsKey, _hideKey, _secretKey]) {
      await _storage.write(key, null);
    }
    if (ref.mounted) {
      state = const ChatLockState();
    }
  }
}

/// The auth repository when the app has one (tests that never set up sign-in
/// have none, and then nobody is signed in).
final authRepositoryProviderOrNull = Provider<AuthRepository?>((ref) {
  try {
    return ref.watch(authRepositoryProvider);
  } on Object {
    return null;
  }
});
