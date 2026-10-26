import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher_provider.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// A member picked from the @mention list while writing a draft, so the
/// mention still counts once the draft is restored and sent.
class DraftMention {
  const DraftMention({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  static DraftMention? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final userId = json['user_id'];
    final username = json['username'];
    if (userId is! String || username is! String) {
      return null;
    }
    return DraftMention(
      userId: userId,
      username: username,
      displayName: json['display_name'] as String? ?? username,
    );
  }

  final String userId;
  final String username;
  final String displayName;

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'username': username,
    'display_name': displayName,
  };
}

/// Unsent composer text of one conversation, channel or thread, with the
/// message it replies to.
class ComposerDraft {
  const ComposerDraft({
    required this.text,
    this.replyToMessageId,
    this.mentions = const [],
  });

  static ComposerDraft? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final text = json['text'];
    if (text is! String) {
      return null;
    }
    return ComposerDraft(
      text: text,
      replyToMessageId: json['reply_to'] as String?,
      mentions: [
        for (final mention in json['mentions'] as List<dynamic>? ?? const [])
          ?DraftMention.fromJson(mention),
      ],
    );
  }

  final String text;
  final String? replyToMessageId;
  final List<DraftMention> mentions;

  /// Nothing worth keeping: no text and no reply.
  bool get isEmpty => text.trim().isEmpty && replyToMessageId == null;

  /// Whether the chat list shows this draft.
  bool get hasText => text.trim().isNotEmpty;

  Map<String, Object?> toJson() => {
    'text': text,
    if (replyToMessageId != null) 'reply_to': replyToMessageId,
    if (mentions.isNotEmpty)
      'mentions': [for (final mention in mentions) mention.toJson()],
  };

  @override
  bool operator ==(Object other) {
    return other is ComposerDraft &&
        other.text == text &&
        other.replyToMessageId == replyToMessageId &&
        other.mentions.length == mentions.length;
  }

  @override
  int get hashCode => Object.hash(text, replyToMessageId, mentions.length);
}

/// Where drafts are kept on this device, per signed-in user; tests swap in
/// memory.
abstract interface class ComposerDraftStore {
  Future<Map<String, ComposerDraft>> load(String userId);

  Future<void> save(String userId, Map<String, ComposerDraft> drafts);
}

/// Drafts in shared preferences, encrypted with the device key (G8); drafts
/// saved before that are read as they are and written back encrypted.
class SharedPreferencesComposerDraftStore implements ComposerDraftStore {
  SharedPreferencesComposerDraftStore({LocalCipher? cipher})
    : cipher = cipher ?? sessionLocalCipher;

  final LocalCipher cipher;

  static String _key(String userId) => 'wecord.chats.$userId.drafts';

  @override
  Future<Map<String, ComposerDraft>> load(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final opened = await cipher.read(preferences.getString(_key(userId)));
    final drafts = decodeComposerDrafts(opened.text);
    if (opened.legacy && drafts.isNotEmpty) {
      await save(userId, drafts);
    }
    return drafts;
  }

  @override
  Future<void> save(String userId, Map<String, ComposerDraft> drafts) async {
    final preferences = await SharedPreferences.getInstance();
    if (drafts.isEmpty) {
      await preferences.remove(_key(userId));
      return;
    }
    await preferences.setString(
      _key(userId),
      await cipher.seal(encodeComposerDrafts(drafts)),
    );
  }
}

class InMemoryComposerDraftStore implements ComposerDraftStore {
  InMemoryComposerDraftStore([Map<String, Map<String, ComposerDraft>>? drafts])
    : drafts = drafts ?? {};

  final Map<String, Map<String, ComposerDraft>> drafts;

  @override
  Future<Map<String, ComposerDraft>> load(String userId) async {
    return {...?drafts[userId]};
  }

  @override
  Future<void> save(String userId, Map<String, ComposerDraft> drafts) async {
    this.drafts[userId] = {...drafts};
  }
}

String encodeComposerDrafts(Map<String, ComposerDraft> drafts) {
  return jsonEncode({
    for (final MapEntry(:key, :value) in drafts.entries) key: value.toJson(),
  });
}

/// Unreadable or missing data reads as no drafts.
Map<String, ComposerDraft> decodeComposerDrafts(String? raw) {
  if (raw == null || raw.isEmpty) {
    return {};
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return {};
    }
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (key is String)
          if (ComposerDraft.fromJson(value) case final draft?
              when !draft.isEmpty)
            key: draft,
    };
  } on FormatException {
    return {};
  }
}

final composerDraftStoreProvider = Provider<ComposerDraftStore>(
  (ref) => SharedPreferencesComposerDraftStore(
    cipher: ref.watch(localCipherProvider),
  ),
);

/// Drafts by conversation id for the signed-in user, kept on this device.
final composerDraftsProvider =
    NotifierProvider<ComposerDraftsController, Map<String, ComposerDraft>>(
      ComposerDraftsController.new,
    );

class ComposerDraftsController extends Notifier<Map<String, ComposerDraft>> {
  /// How long typing has to pause before the drafts are written to the
  /// device. The list in memory (and so the chat list's "[Draft]") follows
  /// every key; only the write waits, since each one stores every draft.
  static const saveDelay = Duration(milliseconds: 400);

  String? _userId;
  final _loaded = Completer<void>();
  var _saving = false;
  var _dirty = false;
  Timer? _saveTimer;

  /// Drafts changed since they were last handed to the store.
  var _unsaved = false;
  late ComposerDraftStore _store;

  /// Completes once the saved drafts have loaded (or failed to).
  Future<void> get loaded => _loaded.future;

  /// The drafts as last set, kept across rebuilds for the same user.
  Map<String, ComposerDraft>? _current;

  @override
  set state(Map<String, ComposerDraft> value) {
    _current = value;
    super.state = value;
  }

  @override
  Map<String, ComposerDraft> build() {
    String? userId;
    try {
      userId =
          ref.watch(authStateProvider.select((state) => state.value?.id)) ??
          ref.read(authRepositoryProvider).currentUser?.id;
    } on Object {
      // No sign-in available (Supabase not set up): drafts stay in memory.
      userId = null;
    }
    final store = ref.read(composerDraftStoreProvider);
    _store = store;
    // Nothing typed is lost when the app goes to the background, is closed
    // or this is rebuilt for another person.
    final lifecycle = _FlushOnLifecycle(() => unawaited(flush()));
    WidgetsBinding.instance.addObserver(lifecycle);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(lifecycle);
      _saveTimer?.cancel();
      _saveTimer = null;
      final owner = _userId;
      final drafts = _current;
      if (_unsaved && owner != null && drafts != null) {
        _unsaved = false;
        unawaited(store.save(owner, drafts).catchError((Object _) {}));
      }
    });
    if (_current case final current? when userId == _userId) {
      return current;
    }
    _userId = userId;
    _current = const {};
    if (userId == null) {
      _complete();
      return const {};
    }
    store
        .load(userId)
        .then(
          (drafts) {
            if (_userId == userId) {
              // Drafts written while loading win over the saved ones.
              state = {...drafts, ...state};
            }
            _complete();
          },
          onError: (Object _) {
            _complete();
          },
        );
    return const {};
  }

  void _complete() {
    if (!_loaded.isCompleted) {
      _loaded.complete();
    }
  }

  ComposerDraft? draftFor(String conversationId) => state[conversationId];

  /// Keeps [draft] for [conversationId]; an empty or null draft removes it.
  ///
  /// Typing is written to the device after a short pause ([saveDelay]); a
  /// draft that goes away (it was sent, or cleared) is written at once, so a
  /// message that left is never offered again after a restart.
  void set(String conversationId, ComposerDraft? draft) {
    final current = state[conversationId];
    if (draft == null || draft.isEmpty) {
      if (current == null) {
        return;
      }
      state = {...state}..remove(conversationId);
      _unsaved = true;
      unawaited(flush());
    } else {
      if (current == draft) {
        return;
      }
      state = {...state, conversationId: draft};
      _unsaved = true;
      _saveTimer?.cancel();
      _saveTimer = Timer(saveDelay, () {
        _saveTimer = null;
        unawaited(_persist());
      });
    }
  }

  /// Writes the drafts now if a write is waiting (leaving the chat, the app
  /// going to the background, a message being sent).
  Future<void> flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_unsaved) {
      return Future.value();
    }
    return _persist();
  }

  /// Writes the latest drafts, one write at a time.
  Future<void> _persist() async {
    final userId = _userId;
    if (userId == null) {
      _unsaved = false;
      return;
    }
    if (_saving) {
      _dirty = true;
      return;
    }
    _saving = true;
    try {
      do {
        _dirty = false;
        _unsaved = false;
        await _store.save(userId, state);
      } while (_dirty);
    } on Object {
      // Drafts still live for this session.
    } finally {
      _saving = false;
    }
  }
}

/// Calls [flush] when the app is no longer in front: the last characters
/// typed are on the device before the system may stop the app.
class _FlushOnLifecycle with WidgetsBindingObserver {
  _FlushOnLifecycle(this.flush);

  final void Function() flush;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      flush();
    }
  }
}

/// "Draft: text" in the chat list, with the label in the error colour.
class DraftPreviewText extends StatelessWidget {
  const DraftPreviewText({required this.draft, this.style, super.key});

  final ComposerDraft draft;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = draft.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return Text.rich(
      key: const ValueKey('conversation-draft'),
      TextSpan(
        children: [
          TextSpan(
            text: tr('[Draft]'),
            style: TextStyle(
              color: colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: ' $text'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
