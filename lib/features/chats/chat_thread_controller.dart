import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/message_window.dart';
import 'package:wecord/features/chats/offline/chat_cache.dart';
import 'package:wecord/features/chats/offline/connectivity.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/storage/local_storage_service.dart';
import 'package:wecord/features/storage/storage_providers.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/message.dart';

/// The open chat's loaded messages and read markers. With a repository
/// that loads history in pages ([MessageHistorySource]) it holds a window
/// of the conversation that grows as the reader scrolls, starts from the
/// offline cache, and takes realtime changes in place; otherwise it loads
/// the whole conversation and reloads on every change.
final chatThreadProvider = AsyncNotifierProvider.autoDispose
    .family<ChatThreadController, ChatThreadData, String>(
      ChatThreadController.new,
    );

class ChatThreadData {
  const ChatThreadData({
    required this.messages,
    required this.readMarkers,
    this.hasOlder = false,
    this.hasNewer = false,
    this.isLoadingOlder = false,
    this.isLoadingNewer = false,
    this.isFromCache = false,
    this.windowVersion = 0,
  });

  /// The loaded messages, oldest first.
  final List<ChatMessage> messages;
  final List<ConversationReadMarker> readMarkers;

  /// Older messages exist beyond the loaded ones.
  final bool hasOlder;

  /// Newer messages exist beyond the loaded ones: the reader jumped back
  /// in history.
  final bool hasNewer;
  final bool isLoadingOlder;
  final bool isLoadingNewer;

  /// Shown from the offline cache; the server has not answered yet.
  final bool isFromCache;

  /// Changes whenever the loaded messages are replaced by another part of
  /// the conversation (a jump to a message, or back to the latest), so
  /// the list knows to move to it.
  final int windowVersion;
}

class ChatThreadController extends AsyncNotifier<ChatThreadData> {
  ChatThreadController(this._conversationId);

  final String _conversationId;
  late ChatsRepository _repository;
  MessageHistorySource? _source;
  ChatCache _cache = const NoChatCache();
  LocalStorageService? _storage;
  String? _userId;

  var _window = MessageWindow.empty;

  /// The raw rows of the loaded messages, for the offline cache.
  final _rows = <String, Map<String, dynamic>>{};
  var _readMarkers = const <ConversationReadMarker>[];
  var _loadingOlder = false;
  var _loadingNewer = false;
  var _fromCache = false;
  var _windowVersion = 0;

  /// Bumped by every build and every window replacement; answers to
  /// requests made before are dropped.
  var _generation = 0;
  var _disposed = true;

  /// Whether build has answered: until then state is left to it.
  var _ready = false;

  final _fetchIds = <String>{};
  final _reactionIds = <String>{};
  var _resyncQueued = false;
  var _markersQueued = false;
  Timer? _flushTimer;
  CacheWriteScheduler? _writes;

  bool get isPaged => _source != null;

  @override
  Future<ChatThreadData> build() async {
    final conversationId = _conversationId;
    _generation++;
    _disposed = false;
    _ready = false;
    _resetWindow();
    final repository = ref.watch(chatsRepositoryProvider);
    _repository = repository;
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      _flushTimer?.cancel();
      _flushTimer = null;
      final writes = _writes;
      _writes = null;
      if (writes != null) {
        unawaited(writes.flushAll().whenComplete(writes.dispose));
      }
    });
    if (repository is! MessageHistorySource) {
      _source = null;
      return _buildWholeConversation(repository, conversationId);
    }
    final source = repository as MessageHistorySource;
    _source = source;
    _cache = ref.watch(chatCacheProvider);
    _storage = ref.read(localStorageServiceProvider);
    _userId = ref.watch(authRepositoryProvider).currentUser?.id;
    _writes = CacheWriteScheduler();

    final subscription = source
        .threadEvents(conversationId)
        .listen(_onEvent, onError: (Object _) {});
    ref.onDispose(subscription.cancel);
    ref.listen<int>(reconnectCountProvider, (previous, next) {
      if (previous != next) {
        unawaited(sync());
      }
    });

    final generation = _generation;
    final cachedRows = await _readCachedRows();
    if (generation != _generation) {
      return _data();
    }
    if (cachedRows.isNotEmpty) {
      _replaceRows(cachedRows);
      _window = MessageWindow(messages: _parse(cachedRows), hasOlder: true);
      _fromCache = true;
      _ready = true;
      // After the cached messages are shown.
      unawaited(Future<void>(sync));
      return _data();
    }

    final results = await Future.wait([
      source.fetchMessageRows(conversationId),
      repository.listReadMarkers(conversationId),
    ]);
    if (generation != _generation) {
      // Rebuilt meanwhile; that build answers.
      return _data();
    }
    final rows = results[0] as List<Map<String, dynamic>>;
    _readMarkers = results[1] as List<ConversationReadMarker>;
    _replaceRows(rows);
    _window = MessageWindow.latest(_parse(rows));
    _scheduleCacheWrite();
    _ready = true;
    return _data();
  }

  Future<ChatThreadData> _buildWholeConversation(
    ChatsRepository repository,
    String conversationId,
  ) async {
    final subscription = repository.threadChanges(conversationId).listen((_) {
      ref.invalidateSelf();
    });
    ref.onDispose(subscription.cancel);
    final results = await Future.wait([
      repository.listMessages(conversationId),
      repository.listReadMarkers(conversationId),
    ]);
    return ChatThreadData(
      messages: results[0] as List<ChatMessage>,
      readMarkers: results[1] as List<ConversationReadMarker>,
    );
  }

  void _resetWindow() {
    _window = MessageWindow.empty;
    _rows.clear();
    _readMarkers = const [];
    _loadingOlder = false;
    _loadingNewer = false;
    _fromCache = false;
    _fetchIds.clear();
    _reactionIds.clear();
    _resyncQueued = false;
    _markersQueued = false;
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  ChatThreadData _data() {
    return ChatThreadData(
      messages: _window.messages,
      readMarkers: _readMarkers,
      hasOlder: _window.hasOlder,
      hasNewer: _window.hasNewer,
      isLoadingOlder: _loadingOlder,
      isLoadingNewer: _loadingNewer,
      isFromCache: _fromCache,
      windowVersion: _windowVersion,
    );
  }

  void _emit() {
    if (!_disposed && _ready) {
      state = AsyncData(_data());
    }
  }

  List<ChatMessage> _parse(Iterable<Map<String, dynamic>> rows) {
    final source = _source!;
    final messages = <ChatMessage>[];
    for (final row in rows) {
      try {
        messages.add(source.messageFromRow(row));
      } catch (_) {
        // A row this version cannot read (a newer server, a damaged
        // cache entry) is left out.
      }
    }
    return messages;
  }

  void _replaceRows(Iterable<Map<String, dynamic>> rows) {
    _rows.clear();
    _addRows(rows);
  }

  void _addRows(Iterable<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final id = row['id'];
      if (id is String) {
        _rows[id] = row;
      }
    }
  }

  void _pruneRows() {
    _rows.removeWhere((id, _) => !_window.contains(id));
  }

  MessageCursor _cursorOf(ChatMessage message) {
    final timestamp = _rows[message.id]?['created_at'];
    return MessageCursor.of(
      message,
      timestamp: timestamp is String ? timestamp : null,
    );
  }

  Future<List<Map<String, dynamic>>> _readCachedRows() async {
    final userId = _userId;
    if (userId == null) {
      return const [];
    }
    try {
      final rows = await _cache.readMessages(userId, _conversationId);
      // A disappearing message whose time ran out while the app was closed
      // is gone, and so is what was kept for it.
      final now = DateTime.now().toUtc();
      final expired = [
        for (final row in rows)
          if (cachedRowExpired(row, now)) row,
      ];
      if (expired.isEmpty) {
        return rows;
      }
      _forget(expired);
      unawaited(
        _cache
            .removeMessages(
              userId,
              _conversationId,
              ids: {for (final row in expired) row['id'] as String},
            )
            .catchError((Object _) {}),
      );
      return [
        for (final row in rows)
          if (!cachedRowExpired(row, now)) row,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Forgets what this device kept for messages that are gone, recalled or
  /// expired: the text read from their pictures, transcripts, downloaded
  /// files and previews.
  void _forget(Iterable<Map<String, dynamic>> rows) {
    final storage = _storage;
    if (storage == null || rows.isEmpty) {
      return;
    }
    final gone = rows.toList();
    unawaited(() async {
      for (final row in gone) {
        try {
          await storage.forgetMessage(row);
        } catch (_) {
          // Only a cache.
        }
      }
    }());
  }

  /// Notes which of the cached [incoming] rows were recalled or expired
  /// since they were last seen, before [incoming] replaces them.
  void _forgetRetired(Iterable<Map<String, dynamic>> incoming) {
    final now = DateTime.now().toUtc();
    final retired = <Map<String, dynamic>>[];
    for (final row in incoming) {
      final previous = _rows[row['id']];
      if (previous == null || previous['recalled_at'] != null) {
        continue;
      }
      if (row['recalled_at'] != null || cachedRowExpired(row, now)) {
        retired.add(previous);
      }
    }
    _forget(retired);
  }

  /// Notes which loaded rows the server no longer has: those as new as the
  /// oldest of [fresh] that are not among them (deleted, or expired and
  /// swept).
  void _forgetMissing(List<Map<String, dynamic>> fresh) {
    if (fresh.isEmpty) {
      return;
    }
    final ids = {for (final row in fresh) row['id']};
    String? floor;
    for (final row in fresh) {
      final at = row['created_at'];
      if (at is String && (floor == null || at.compareTo(floor) < 0)) {
        floor = at;
      }
    }
    if (floor == null) {
      return;
    }
    final lowest = DateTime.tryParse(floor);
    if (lowest == null) {
      return;
    }
    _forget([
      for (final row in _rows.values)
        if (!ids.contains(row['id']) &&
            _createdAtOrAfter(row['created_at'], lowest))
          row,
    ]);
  }

  static bool _createdAtOrAfter(Object? value, DateTime floor) {
    if (value is! String) {
      return false;
    }
    final at = DateTime.tryParse(value);
    return at != null && !at.isBefore(floor);
  }

  void _scheduleCacheWrite() {
    final userId = _userId;
    final writes = _writes;
    if (userId == null || writes == null || !_window.isLive) {
      return;
    }
    final rows = [
      for (final message in _window.newestMessages(
        cachedMessagesPerConversation,
      ))
        ?_rows[message.id],
    ];
    final cache = _cache;
    final conversationId = _conversationId;
    writes.schedule(
      'messages',
      () => cache.writeMessages(userId, conversationId, rows),
    );
  }

  /// Loads the page before the oldest loaded message.
  Future<void> loadOlder() async {
    final source = _source;
    if (source == null ||
        _disposed ||
        _loadingOlder ||
        !_window.hasOlder ||
        _window.isEmpty) {
      return;
    }
    final generation = _generation;
    final cursor = _cursorOf(_window.messages.first);
    _loadingOlder = true;
    _emit();
    try {
      final rows = await source.fetchMessageRows(
        _conversationId,
        before: cursor,
      );
      if (generation != _generation) {
        return;
      }
      _addRows(rows);
      _window = _window.withOlder(_parse(rows));
    } catch (_) {
      // Tried again when the reader scrolls on.
    } finally {
      if (generation == _generation) {
        _loadingOlder = false;
        _emit();
      }
    }
  }

  /// Loads the page after the newest loaded message, when the reader
  /// jumped back in history.
  Future<void> loadNewer() async {
    final source = _source;
    if (source == null ||
        _disposed ||
        _loadingNewer ||
        !_window.hasNewer ||
        _window.isEmpty) {
      return;
    }
    final generation = _generation;
    final cursor = _cursorOf(_window.messages.last);
    _loadingNewer = true;
    _emit();
    try {
      final rows = await source.fetchMessageRows(
        _conversationId,
        after: cursor,
      );
      if (generation != _generation) {
        return;
      }
      _addRows(rows);
      _window = _window.withNewer(_parse(rows));
      _scheduleCacheWrite();
    } catch (_) {
      // Tried again when the reader scrolls on.
    } finally {
      if (generation == _generation) {
        _loadingNewer = false;
        _emit();
      }
    }
  }

  /// Makes sure [messageId] is loaded, loading the pages around it when
  /// it is not. Returns false when the message cannot be found.
  Future<bool> jumpTo(String messageId) async {
    if (_window.contains(messageId)) {
      return true;
    }
    final source = _source;
    if (source == null || _disposed) {
      return false;
    }
    final generation = _generation;
    try {
      final targets = await source.fetchMessageRowsByIds(_conversationId, [
        messageId,
      ]);
      if (targets.isEmpty || generation != _generation) {
        return false;
      }
      final targetRow = targets.first;
      final target = _parse([targetRow]).firstOrNull;
      if (target == null) {
        return false;
      }
      final cursor = MessageCursor.of(
        target,
        timestamp: targetRow['created_at'] as String?,
      );
      const half = messagePageSize ~/ 2;
      final pages = await Future.wait([
        source.fetchMessageRows(_conversationId, before: cursor, limit: half),
        source.fetchMessageRows(_conversationId, after: cursor, limit: half),
      ]);
      if (generation != _generation) {
        return false;
      }
      _generation++;
      _replaceRows([...pages[0], targetRow, ...pages[1]]);
      _window = MessageWindow.around(
        target,
        before: _parse(pages[0]),
        after: _parse(pages[1]),
        limit: half,
      );
      _loadingOlder = false;
      _loadingNewer = false;
      _windowVersion++;
      _emit();
      _scheduleCacheWrite();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Back to the conversation's newest messages after a jump.
  Future<void> jumpToLatest() async {
    final source = _source;
    if (source == null || _disposed || _window.isLive) {
      return;
    }
    final generation = _generation;
    try {
      final rows = await source.fetchMessageRows(_conversationId);
      if (generation != _generation) {
        return;
      }
      _generation++;
      _replaceRows(rows);
      _window = MessageWindow.latest(_parse(rows));
      _loadingOlder = false;
      _loadingNewer = false;
      _windowVersion++;
      _emit();
      _scheduleCacheWrite();
    } catch (_) {
      // Stays where it is.
    }
  }

  /// Forum posts read from their opening post: loads the conversation's
  /// first page when the newest page does not reach back to it.
  Future<void> startFromBeginning() async {
    final source = _source;
    if (source == null || _disposed || !_window.hasOlder) {
      return;
    }
    final generation = _generation;
    try {
      final rows = await source.fetchMessageRows(
        _conversationId,
        after: MessageCursor(
          DateTime.utc(1970),
          '00000000-0000-0000-0000-000000000000',
          timestamp: '1970-01-01T00:00:00Z',
        ),
      );
      if (generation != _generation) {
        return;
      }
      _generation++;
      _replaceRows(rows);
      _window = MessageWindow.earliest(_parse(rows));
      _windowVersion++;
      _emit();
    } catch (_) {
      // Keeps the newest page.
    }
  }

  /// Brings the loaded messages up to date: after an action on
  /// [messageId] just that message, otherwise the newest page and the
  /// read markers. Without paged history the conversation reloads.
  Future<void> refresh({String? messageId}) async {
    if (_source == null) {
      ref.invalidateSelf();
      return;
    }
    if (messageId != null && !isPendingMessageId(messageId)) {
      _fetchIds.add(messageId);
      _reactionIds.add(messageId);
      await _flush();
      return;
    }
    await sync();
  }

  /// Puts a message the current user just sent in place (once the outbox
  /// hears it was stored), before its pending copy goes away.
  Future<void> ingestSent(String messageId) async {
    if (_source == null || !_window.isLive || _window.contains(messageId)) {
      return;
    }
    _fetchIds.add(messageId);
    await _flush();
  }

  /// Takes the conversation's newest page and read markers as the truth
  /// (after the offline cache, a reconnect or a missed realtime change).
  /// Offline, keeps what is shown.
  Future<void> sync() async {
    final source = _source;
    if (source == null || _disposed) {
      return;
    }
    final generation = _generation;
    try {
      final results = await Future.wait([
        source.fetchMessageRows(_conversationId),
        _repository.listReadMarkers(_conversationId),
      ]);
      if (generation != _generation) {
        return;
      }
      final rows = results[0] as List<Map<String, dynamic>>;
      _readMarkers = results[1] as List<ConversationReadMarker>;
      if (_window.isLive) {
        _forgetRetired(rows);
        _forgetMissing(rows);
        _addRows(rows);
        _window = _window.syncWithLatest(_parse(rows));
        _pruneRows();
        _scheduleCacheWrite();
      }
      _fromCache = false;
      _emit();
    } catch (_) {
      // Offline: the cached messages stay.
    }
  }

  void _onEvent(ThreadEvent event) {
    if (_disposed) {
      return;
    }
    final messageId = event.messageId;
    switch (event.kind) {
      case ThreadEventKind.messageInserted:
        // New messages are the newest: they belong in a live window only.
        if (messageId != null && _window.isLive) {
          _fetchIds.add(messageId);
        }
      case ThreadEventKind.messageUpdated:
      case ThreadEventKind.pollVotesChanged:
      case ThreadEventKind.pinsChanged:
      case ThreadEventKind.threadsChanged:
        if (messageId == null) {
          _resyncQueued = true;
        } else if (_window.contains(messageId)) {
          _fetchIds.add(messageId);
        }
      case ThreadEventKind.reactionsChanged:
        if (messageId == null) {
          _resyncQueued = true;
        } else if (_window.contains(messageId)) {
          _reactionIds.add(messageId);
        }
      case ThreadEventKind.messageDeleted:
        if (messageId != null && _window.contains(messageId)) {
          _forget([
            _rows[messageId] ?? {'id': messageId},
          ]);
          _window = _window.remove([messageId]);
          _rows.remove(messageId);
          _emit();
          _scheduleCacheWrite();
        }
        return;
      case ThreadEventKind.membersChanged:
        _markersQueued = true;
      case ThreadEventKind.resubscribed:
        _resyncQueued = true;
    }
    // Changes come in bursts (a message and its mentions, several
    // reactions): handle them together.
    _flushTimer ??= Timer(const Duration(milliseconds: 60), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    final source = _source;
    if (source == null || _disposed) {
      return;
    }
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_ready) {
      // The first page is still loading; changes wait for it.
      _flushTimer = Timer(const Duration(milliseconds: 200), () {
        _flushTimer = null;
        unawaited(_flush());
      });
      return;
    }
    final generation = _generation;
    final fetchIds = [..._fetchIds];
    final reactionIds = [
      for (final id in _reactionIds)
        if (!_fetchIds.contains(id)) id,
    ];
    final resync = _resyncQueued;
    final markers = _markersQueued && !resync;
    _fetchIds.clear();
    _reactionIds.clear();
    _resyncQueued = false;
    _markersQueued = false;
    try {
      if (resync) {
        await sync();
      }
      if (markers) {
        final readMarkers = await _repository.listReadMarkers(_conversationId);
        if (generation != _generation) {
          return;
        }
        _readMarkers = readMarkers;
      }
      if (fetchIds.isNotEmpty) {
        final rows = <Map<String, dynamic>>[];
        for (var start = 0; start < fetchIds.length; start += 100) {
          final end = start + 100 < fetchIds.length
              ? start + 100
              : fetchIds.length;
          rows.addAll(
            await source.fetchMessageRowsByIds(
              _conversationId,
              fetchIds.sublist(start, end),
            ),
          );
        }
        if (generation != _generation) {
          return;
        }
        final found = {for (final row in rows) row['id']};
        _forgetRetired(rows);
        _addRows(rows);
        _window = _window.upsert(_parse(rows)).remove([
          for (final id in fetchIds)
            if (!found.contains(id)) id,
        ]);
        _pruneRows();
      }
      if (reactionIds.isNotEmpty) {
        final reactions = await source.fetchReactions(
          _conversationId,
          reactionIds,
        );
        if (generation != _generation) {
          return;
        }
        final updated = <Map<String, dynamic>>[];
        for (final id in reactionIds) {
          final row = _rows[id];
          if (row != null) {
            updated.add({...row, 'reactions': reactions[id] ?? const []});
          }
        }
        _addRows(updated);
        _window = _window.upsert(_parse(updated));
      }
      _emit();
      _scheduleCacheWrite();
    } catch (_) {
      // Offline or failing: the next change or reconnect syncs.
    }
  }
}
