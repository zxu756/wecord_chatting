import 'dart:async';

/// Gathers the chains asked for within a moment into one request.
///
/// A chat with many chain cards builds a dozen of them in one frame while
/// scrolling; each asks for its chain. They share one `get_chains` call
/// (at most [maxBatch] chains each) instead of one `get_chain` apiece. A chain
/// asked for twice in a moment is read once and both askers get the answer.
class ChainReadBatcher<T> {
  ChainReadBatcher(
    this._fetch, {
    this.delay = const Duration(milliseconds: 25),
    this.maxBatch = 50,
  });

  /// Reads these chains; answers by chain id (a chain that is missing from
  /// the answer is not available to the caller).
  final Future<Map<String, T>> Function(List<String> chainIds) _fetch;

  /// How long to wait for more chains to ask before reading.
  final Duration delay;
  final int maxBatch;

  final _waiting = <String, List<Completer<T>>>{};
  Timer? _timer;

  /// The number of requests made so far (for tests and diagnostics).
  var requests = 0;

  Future<T> read(String chainId) {
    final completer = Completer<T>();
    (_waiting[chainId] ??= []).add(completer);
    _timer ??= Timer(delay, _flush);
    return completer.future;
  }

  void _flush() {
    _timer = null;
    final batch = Map.of(_waiting);
    _waiting.clear();
    final ids = batch.keys.toList(growable: false);
    for (var start = 0; start < ids.length; start += maxBatch) {
      final end = start + maxBatch < ids.length ? start + maxBatch : ids.length;
      unawaited(
        _run({for (final id in ids.sublist(start, end)) id: batch[id]!}),
      );
    }
  }

  Future<void> _run(Map<String, List<Completer<T>>> chunk) async {
    requests += 1;
    try {
      final answers = await _fetch(chunk.keys.toList(growable: false));
      for (final MapEntry(key: id, value: completers) in chunk.entries) {
        final answer = answers[id];
        for (final completer in completers) {
          if (answer != null) {
            completer.complete(answer);
          } else {
            completer.completeError(const ChainNotAvailable());
          }
        }
      }
    } on Object catch (error, stackTrace) {
      for (final completers in chunk.values) {
        for (final completer in completers) {
          completer.completeError(error, stackTrace);
        }
      }
    }
  }
}

/// The batch had no answer for this chain.
class ChainNotAvailable implements Exception {
  const ChainNotAvailable();
}

/// Opens the one source of changes for a conversation's chains and returns
/// the function that closes it. [onChange] is called with the id of the
/// chain that changed, or null when it is not known (every chain of the
/// conversation then reads again).
typedef ChainChannelOpener =
    FutureOr<void> Function() Function(
      String conversationId,
      void Function(String? chainId) onChange,
    );

/// One source of changes per conversation, shared by every chain card (and
/// sheet) of it, however many are on screen.
///
/// Cards ask for the changes of their chain; the first of a conversation
/// opens its channel and the last one to stop listening closes it [grace]
/// later (a card that scrolls away and comes back should not reopen it).
///
/// The channel is named for the conversation, `chains:<conversation id>`, and
/// carries the changes of `public.chains` filtered to that conversation:
/// Postgres Changes, which the table's row level security already limits to
/// people who may read the chain. When channels become private (Realtime
/// Authorization), a policy on `realtime.messages` for the topic
/// `chains:<conversation id>` that checks the caller is a member of that
/// conversation is all this needs; see [ChainChangeHub.topicFor].
class ChainChangeHub {
  ChainChangeHub(this._open, {this.grace = const Duration(seconds: 3)});

  final ChainChannelOpener _open;
  final Duration grace;

  /// The Realtime topic of a conversation's chains.
  static String topicFor(String conversationId) => 'chains:$conversationId';

  final _conversationOf = <String, String>{};
  final _feeds = <String, _Feed>{};

  /// Listeners whose chain's conversation is not known yet: it is learned
  /// from the first read of the chain.
  final _waiting = <String, Set<_Listener>>{};

  /// Channels open right now (for tests and diagnostics).
  int get openChannels => _feeds.values.where((f) => f.close != null).length;

  /// The chain belongs to this conversation (learned from reading it).
  void learn(String chainId, String conversationId) {
    _conversationOf[chainId] = conversationId;
    final waiting = _waiting.remove(chainId);
    if (waiting == null) {
      return;
    }
    for (final listener in waiting) {
      _attach(listener, conversationId);
    }
  }

  /// Fires whenever this chain changes. Listening opens (or joins) the
  /// conversation's channel; cancelling lets go of it.
  Stream<void> changes(String chainId) {
    late StreamController<void> controller;
    _Listener? listener;
    controller = StreamController<void>(
      onListen: () {
        listener = _Listener(chainId, controller);
        final conversationId = _conversationOf[chainId];
        if (conversationId == null) {
          (_waiting[chainId] ??= {}).add(listener!);
        } else {
          _attach(listener!, conversationId);
        }
      },
      onCancel: () {
        final done = listener;
        if (done == null) {
          return;
        }
        _waiting[chainId]?.remove(done);
        if (_waiting[chainId]?.isEmpty ?? false) {
          _waiting.remove(chainId);
        }
        final feed = done.feed;
        if (feed != null) {
          feed.listeners.remove(done);
          _maybeClose(feed);
        }
      },
    );
    return controller.stream;
  }

  void _attach(_Listener listener, String conversationId) {
    if (listener.controller.isClosed) {
      return;
    }
    final feed = _feeds.putIfAbsent(
      conversationId,
      () => _Feed(conversationId),
    );
    feed.closeTimer?.cancel();
    feed.closeTimer = null;
    feed.listeners.add(listener);
    listener.feed = feed;
    feed.close ??= _open(conversationId, (chainId) => _deliver(feed, chainId));
  }

  void _deliver(_Feed feed, String? chainId) {
    for (final listener in feed.listeners.toList(growable: false)) {
      if ((chainId == null || listener.chainId == chainId) &&
          !listener.controller.isClosed) {
        listener.controller.add(null);
      }
    }
  }

  void _maybeClose(_Feed feed) {
    if (feed.listeners.isNotEmpty) {
      return;
    }
    feed.closeTimer?.cancel();
    feed.closeTimer = Timer(grace, () {
      feed.closeTimer = null;
      if (feed.listeners.isNotEmpty) {
        return;
      }
      final close = feed.close;
      feed.close = null;
      _feeds.remove(feed.conversationId);
      if (close != null) {
        unawaited(Future<void>.sync(close));
      }
    });
  }

  /// Closes every channel now.
  void dispose() {
    for (final feed in _feeds.values) {
      feed.closeTimer?.cancel();
      final close = feed.close;
      feed.close = null;
      if (close != null) {
        unawaited(Future<void>.sync(close));
      }
    }
    _feeds.clear();
    _waiting.clear();
  }
}

class _Feed {
  _Feed(this.conversationId);

  final String conversationId;
  final listeners = <_Listener>{};
  FutureOr<void> Function()? close;
  Timer? closeTimer;
}

class _Listener {
  _Listener(this.chainId, this.controller);

  final String chainId;
  final StreamController<void> controller;
  _Feed? feed;
}
