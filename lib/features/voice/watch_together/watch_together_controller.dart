import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart' as call_session;
import 'package:wecord/features/voice/watch_together/watch_media.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';

/// Why a showing ended, shown to the people who were watching.
enum WatchNotice {
  none,

  /// The host ended it.
  hostEnded,

  /// The host left the call, or has not been heard for a while.
  hostLeft,
}

/// Watching together in the call this device is in. Lives in memory only.
@immutable
class WatchTogetherState {
  const WatchTogetherState({
    this.active = false,
    this.sessionId,
    this.hostId,
    this.isHost = false,
    this.link,
    this.title = '',
    this.anchor,
    this.dismissed = false,
    this.hidden = false,
    this.muted = false,
    this.needsTap = false,
    this.notice = WatchNotice.none,
    this.noticeName,
    this.names = const {},
    this.playerEpoch = 0,
    this.callKey,
  });

  /// Someone in the call is sharing something to watch.
  final bool active;

  /// Names this showing, so late packets of an old one are ignored.
  final String? sessionId;

  /// Who shares it (a user id): the only person whose play, pause and seek
  /// count.
  final String? hostId;

  /// This person is the host.
  final bool isHost;
  final WatchLink? link;
  final String title;

  /// Where the host is, as far as this device knows.
  final WatchAnchor? anchor;

  /// This person stopped watching on their own side; the host and everyone
  /// else go on.
  final bool dismissed;

  /// This person hides the picture on their own screen (the sound goes on).
  final bool hidden;

  /// The sound is off on this device only.
  final bool muted;

  /// The browser or device did not let the media start by itself: one tap
  /// on the picture starts it.
  final bool needsTap;

  /// Why the last showing ended, for a few seconds.
  final WatchNotice notice;
  final String? noticeName;

  /// Names of everyone seen in the call, by user id.
  final Map<String, String> names;

  /// Counts the players this device has made, so the picture is rebuilt.
  final int playerEpoch;

  /// Which call this is about (conversation / channel / call ids).
  final String? callKey;

  String? nameOf(String userId) => names[userId];

  /// The host's name, when known.
  String? get hostName => hostId == null ? null : names[hostId];

  /// Whether the app plays the media and keeps it in step.
  bool get synced => link?.synced ?? false;

  WatchTogetherState copyWith({
    bool? dismissed,
    bool? hidden,
    bool? muted,
    bool? needsTap,
    WatchNotice? notice,
    Object? noticeName = _keep,
    Map<String, String>? names,
    int? playerEpoch,
    Object? anchor = _keep,
  }) {
    return WatchTogetherState(
      active: active,
      sessionId: sessionId,
      hostId: hostId,
      isHost: isHost,
      link: link,
      title: title,
      anchor: identical(anchor, _keep) ? this.anchor : anchor as WatchAnchor?,
      dismissed: dismissed ?? this.dismissed,
      hidden: hidden ?? this.hidden,
      muted: muted ?? this.muted,
      needsTap: needsTap ?? this.needsTap,
      notice: notice ?? this.notice,
      noticeName: identical(noticeName, _keep)
          ? this.noticeName
          : noticeName as String?,
      names: names ?? this.names,
      playerEpoch: playerEpoch ?? this.playerEpoch,
      callKey: callKey,
    );
  }
}

const Object _keep = Object();

/// The clock watching uses for times and pauses; tests set their own.
final watchClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Makes the id of a showing; tests set their own.
final watchIdProvider = Provider<String Function()>((ref) {
  final random = math.Random.secure();
  return () {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(
      16,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  };
});

/// Watching together (E4).
///
/// How it works: whoever starts sharing a link is the host. Only the host's
/// play, pause, seek, new link and end are accepted; the host repeats where
/// they are every few seconds, and says it all again when someone joins or
/// asks. Everybody else loads the link on their own device and moves to the
/// host's position whenever they are more than a second away. Only these
/// small control messages travel through the call: the video or sound
/// itself is never sent.
final watchTogetherProvider =
    NotifierProvider<WatchTogetherController, WatchTogetherState>(
      WatchTogetherController.new,
    );

class WatchTogetherController extends Notifier<WatchTogetherState> {
  late final DateTime Function() _now;
  late final String Function() _newId;
  call_session.VoiceSession? _session;
  StreamSubscription<VoiceDataMessage>? _data;
  WatchMediaPlayer? _player;
  Timer? _tickTimer;
  Timer? _noticeTimer;
  late final _limits = WatchRateLimits(now: () => _now());
  DateTime? _heardHostAt;
  DateTime? _lastBeat;
  DateTime? _lastRestate;
  DateTime? _lastAsk;
  DateTime? _lastSeek;
  var _seq = 0;
  var _lastSeq = -1;
  var _readyHandled = false;
  var _pendingHostPlay = false;
  var _stalls = 0;

  @override
  WatchTogetherState build() {
    _now = ref.read(watchClockProvider);
    _newId = ref.read(watchIdProvider);
    _limits.clear();
    final controller = ref.read(call_session.voiceSessionProvider.notifier);
    _data = controller.dataMessages.listen(_onData);
    ref.listen(call_session.voiceSessionProvider, (previous, next) {
      _onSession(next);
    });
    ref.onDispose(() {
      unawaited(_data?.cancel());
      _tickTimer?.cancel();
      _noticeTimer?.cancel();
      _disposePlayer();
    });
    final session = ref.read(call_session.voiceSessionProvider);
    _session = session;
    return WatchTogetherState(
      callKey: _keyOf(session),
      names: {
        for (final participant in session?.participants ?? const [])
          participant.userId: participant.name,
      },
    );
  }

  /// The player of the showing, for the picture and the controls; null
  /// before it exists, after this person stopped watching, and for web
  /// pages.
  WatchMediaPlayer? get player => _player;

  // --------------------------------------------------------- the session --

  static String? _keyOf(call_session.VoiceSession? session) {
    if (session == null || !session.isConnected) {
      return null;
    }
    return '${session.conversationId}/${session.channelId ?? ''}/${session.callId ?? ''}';
  }

  VoiceCallParticipant? get _me {
    for (final participant in _session?.participants ?? const []) {
      if (participant.isLocal) {
        return participant;
      }
    }
    return null;
  }

  VoiceCallParticipant? _participant(String userId) {
    for (final participant in _session?.participants ?? const []) {
      if (participant.userId == userId) {
        return participant;
      }
    }
    return null;
  }

  /// This person can start a showing now: they are in a connected call and
  /// nothing is on, or they are the host and can change what is on.
  bool get canStart =>
      _session?.isConnected == true && (!state.active || state.isHost);

  void _onSession(call_session.VoiceSession? session) {
    final previous = _session;
    _session = session;
    final key = _keyOf(session);
    if (key != state.callKey) {
      _reset(key);
      if (key == null) {
        return;
      }
    }
    if (session == null || !session.isConnected) {
      return;
    }
    final names = {...state.names};
    for (final participant in session.participants) {
      names[participant.userId] = participant.name;
    }
    if (!mapEquals(names, state.names)) {
      state = state.copyWith(names: names);
    }
    if (!state.active) {
      return;
    }
    final host = state.hostId;
    if (!state.isHost && host != null && _participant(host) == null) {
      // The host left the call: it ends with them.
      _deactivate(WatchNotice.hostLeft, name: state.names[host]);
      return;
    }
    if (state.isHost &&
        previous != null &&
        session.participants.length > previous.participants.length) {
      // Somebody joined: tell them what is on.
      _restate();
    }
  }

  void _reset(String? key) {
    _tickTimer?.cancel();
    _tickTimer = null;
    _noticeTimer?.cancel();
    _noticeTimer = null;
    _disposePlayer();
    _limits.clear();
    _heardHostAt = null;
    _lastBeat = null;
    _lastRestate = null;
    _lastAsk = null;
    _lastSeek = null;
    _seq = 0;
    _lastSeq = -1;
    _stalls = 0;
    _pendingHostPlay = false;
    state = WatchTogetherState(callKey: key, muted: state.muted);
  }

  // ------------------------------------------------------ host's actions --

  /// Starts sharing [input] (a link) to watch or listen to together, as the
  /// host; as the host already, switches to the new link. Returns why the
  /// link was not accepted, or null when it is on.
  Future<WatchLinkProblem?> start(String input, {String title = ''}) async {
    if (!canStart) {
      return WatchLinkProblem.invalid;
    }
    final result = parseWatchLink(input);
    final link = result.link;
    if (link == null) {
      return result.problem;
    }
    final me = _me!.userId;
    final now = _now();
    _disposePlayer();
    _seq = 0;
    _lastSeq = -1;
    _stalls = 0;
    final shownTitle = tidyWatchTitle(title);
    final anchor = WatchAnchor(positionMs: 0, at: now, playing: false);
    final id = _newId();
    state = WatchTogetherState(
      active: true,
      sessionId: id,
      hostId: me,
      isHost: true,
      link: link,
      title: shownTitle.isEmpty ? link.fallbackTitle : shownTitle,
      anchor: anchor,
      muted: state.muted,
      names: state.names,
      playerEpoch: state.playerEpoch,
      callKey: state.callKey,
    );
    _heardHostAt = now;
    _pendingHostPlay = link.synced;
    _startTicking();
    if (link.synced) {
      _openPlayer();
    }
    await _publishStart();
    return null;
  }

  /// Ends it for everyone. Only the host.
  Future<void> end() async {
    if (!state.active || !state.isHost) {
      return;
    }
    final id = state.sessionId!;
    await _publish(encodeWatchEnd(id: id, seq: ++_seq));
    _deactivate(WatchNotice.none);
  }

  /// The host plays from where they are.
  Future<void> play() async {
    final player = _player;
    if (!state.isHost || player == null || !player.value.ready) {
      return;
    }
    await player.play();
    _hostAnchor(_hostPositionMs(), playing: true);
    await _publishSync(WatchCause.play);
  }

  /// The host pauses.
  Future<void> pause() async {
    final player = _player;
    if (!state.isHost || player == null || !player.value.ready) {
      return;
    }
    await player.pause();
    _hostAnchor(_hostPositionMs(), playing: false);
    await _publishSync(WatchCause.pause);
  }

  /// The host jumps to [position].
  Future<void> seek(Duration position) async {
    final player = _player;
    if (!state.isHost || player == null || !player.value.ready) {
      return;
    }
    final duration = player.value.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (duration > Duration.zero && target > duration) {
      target = duration;
    }
    await player.seekTo(target);
    _hostAnchor(target.inMilliseconds, playing: state.anchor?.playing ?? false);
    await _publishSync(WatchCause.seek);
  }

  int _hostPositionMs() {
    final player = _player;
    if (player != null && player.value.ready) {
      return player.value.position.inMilliseconds;
    }
    return state.anchor?.expectedMs(_now()) ?? 0;
  }

  void _hostAnchor(int positionMs, {required bool playing}) {
    state = state.copyWith(
      anchor: WatchAnchor(positionMs: positionMs, at: _now(), playing: playing),
      needsTap: false,
    );
  }

  Future<void> _publishStart() {
    final anchor = _currentAnchor();
    return _publish(
      encodeWatchStart(
        id: state.sessionId!,
        link: state.link!,
        title: state.title,
        positionMs: anchor.positionMs,
        playing: anchor.playing,
        seq: ++_seq,
        sentAt: _now(),
      ),
    );
  }

  /// Where the host is right now, as an anchor at this moment.
  WatchAnchor _currentAnchor() {
    final playing = state.anchor?.playing ?? false;
    return WatchAnchor(
      positionMs: _hostPositionMs(),
      at: _now(),
      playing: playing,
    );
  }

  Future<void> _publishSync(WatchCause cause) {
    final anchor = _currentAnchor();
    return _publish(
      encodeWatchSync(
        id: state.sessionId!,
        cause: cause,
        positionMs: anchor.positionMs,
        playing: anchor.playing,
        seq: ++_seq,
        sentAt: _now(),
      ),
      reliable: cause != WatchCause.beat,
    );
  }

  Future<void> _publish(List<int> data, {bool reliable = true}) async {
    if (!ref.mounted) {
      return;
    }
    await ref
        .read(call_session.voiceSessionProvider.notifier)
        .publishData(data, topic: watchTopic, reliable: reliable);
  }

  void _restate() {
    final now = _now();
    final last = _lastRestate;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastRestate = now;
    unawaited(_publishStart());
  }

  // ------------------------------------------------------- my own choice --

  /// Silences (or restores) the sound on this device only.
  Future<void> setMuted(bool muted) async {
    if (muted != state.muted) {
      state = state.copyWith(muted: muted);
    }
    await _player?.setMuted(muted);
  }

  /// Hides (or shows) the picture on this screen only.
  void setHidden(bool hidden) {
    if (hidden != state.hidden) {
      state = state.copyWith(hidden: hidden);
    }
  }

  /// Stops watching on this device only. Everyone else goes on, and this
  /// person can [rejoin].
  void leaveMine() {
    if (!state.active || state.isHost || state.dismissed) {
      return;
    }
    _disposePlayer();
    state = state.copyWith(dismissed: true, needsTap: false, hidden: false);
  }

  /// Watches again after [leaveMine], from where the host is.
  void rejoin() {
    if (!state.active || !state.dismissed) {
      return;
    }
    state = state.copyWith(dismissed: false);
    if (state.synced) {
      _openPlayer();
    }
  }

  /// One tap starts the media where the device did not let it start alone.
  Future<void> tapToPlay() async {
    final player = _player;
    state = state.copyWith(needsTap: false);
    _stalls = 0;
    if (player == null || !player.value.ready) {
      return;
    }
    _align(force: true);
  }

  void clearNotice() {
    _noticeTimer?.cancel();
    if (state.notice != WatchNotice.none) {
      state = state.copyWith(notice: WatchNotice.none, noticeName: null);
    }
  }

  // ------------------------------------------------------ the media side --

  void _openPlayer() {
    final link = state.link;
    if (link == null || !link.synced) {
      return;
    }
    _disposePlayer();
    final player = ref.read(watchPlayerFactoryProvider)();
    _player = player;
    _readyHandled = false;
    _stalls = 0;
    player.addListener(_onPlayerValue);
    state = state.copyWith(playerEpoch: state.playerEpoch + 1);
    unawaited(
      Future.sync(() async {
        if (state.muted) {
          await player.setMuted(true);
        }
        await player.open(link);
      }),
    );
  }

  void _disposePlayer() {
    final player = _player;
    _player = null;
    if (player != null) {
      player.removeListener(_onPlayerValue);
      unawaited(player.dispose());
    }
  }

  void _onPlayerValue() {
    final player = _player;
    if (player == null || !ref.mounted) {
      return;
    }
    if (player.value.ready && !_readyHandled) {
      _readyHandled = true;
      unawaited(_onReady(player));
    }
  }

  Future<void> _onReady(WatchMediaPlayer player) async {
    if (state.isHost) {
      if (_pendingHostPlay) {
        _pendingHostPlay = false;
        // The host presses play for everyone once their own copy is ready.
        await player.seekTo(Duration.zero);
        await play();
      }
      return;
    }
    _align(force: true);
  }

  // ----------------------------------------------------------- the clock --

  void _startTicking() {
    _tickTimer?.cancel();
    _lastBeat = _now();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!ref.mounted || !state.active) {
      return;
    }
    final now = _now();
    if (state.isHost) {
      _hostTick(now);
      return;
    }
    final heard = _heardHostAt;
    if (heard != null && now.difference(heard) > watchHostTimeout) {
      _deactivate(WatchNotice.hostLeft, name: state.hostName);
      return;
    }
    _align();
  }

  void _hostTick(DateTime now) {
    final player = _player;
    final anchor = state.anchor;
    if (player != null && anchor != null) {
      final v = player.value;
      final finished =
          v.ready &&
          anchor.playing &&
          !v.playing &&
          !v.buffering &&
          v.duration > Duration.zero &&
          v.position >= v.duration - const Duration(milliseconds: 300);
      if (finished) {
        // It played to the end: everyone stops there.
        _hostAnchor(v.duration.inMilliseconds, playing: false);
        unawaited(_publishSync(WatchCause.pause));
        _lastBeat = now;
        return;
      }
    }
    final last = _lastBeat;
    if (last == null || now.difference(last) >= watchHeartbeat) {
      _lastBeat = now;
      unawaited(_publishSync(WatchCause.beat));
    }
  }

  /// Moves this device's player to where the host is: starts or stops it,
  /// and seeks when it is more than [watchDriftTolerance] away. [force]
  /// skips the pause that keeps a seek from being repeated while it settles.
  void _align({bool force = false}) {
    final player = _player;
    final anchor = state.anchor;
    if (player == null ||
        anchor == null ||
        state.dismissed ||
        !player.value.ready) {
      return;
    }
    final v = player.value;
    final now = _now();
    final duration = v.duration.inMilliseconds;
    final target = anchor.expectedMs(now, durationMs: duration);
    final wantPlay = anchor.playing && (duration <= 0 || target < duration);

    final lastSeek = _lastSeek;
    final settled =
        force ||
        lastSeek == null ||
        now.difference(lastSeek) >= const Duration(milliseconds: 1500);
    if (settled &&
        watchNeedsSeek(
          localMs: v.position.inMilliseconds,
          expectedMs: target,
        )) {
      _lastSeek = now;
      unawaited(_guard(() => player.seekTo(Duration(milliseconds: target))));
    }
    if (wantPlay && !v.playing) {
      unawaited(_guard(player.play));
      if (!v.buffering) {
        _stalls++;
        if (_stalls >= 2 && !state.needsTap) {
          state = state.copyWith(needsTap: true);
        }
      }
    } else if (!wantPlay) {
      _stalls = 0;
      if (v.playing) {
        unawaited(_guard(player.pause));
      }
      if (state.needsTap) {
        state = state.copyWith(needsTap: false);
      }
    } else {
      _stalls = 0;
      if (state.needsTap) {
        state = state.copyWith(needsTap: false);
      }
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // The device refused (a browser that wants a tap first); the next
      // tick tries again, and the picture asks for a tap.
    }
  }

  // ------------------------------------------------------ received data --

  void _onData(VoiceDataMessage message) {
    if (message.topic != watchTopic || !ref.mounted) {
      return;
    }
    final session = _session;
    final me = _me?.userId;
    if (session == null || !session.isConnected || me == null) {
      return;
    }
    final sender = message.senderId;
    // Only people the voice server says are in this call count.
    if (sender == me || _participant(sender) == null) {
      return;
    }
    if (!_limits.allow(sender)) {
      return;
    }
    final packet = decodeWatchPacket(message.data);
    if (packet == null) {
      return;
    }
    switch (packet) {
      case final WatchStartPacket start:
        _onStart(sender, start, me);
      case final WatchSyncPacket sync:
        _onSync(sender, sync);
      case final WatchEndPacket end:
        _onEnd(sender, end);
      case WatchAskPacket():
        if (state.active && state.isHost) {
          _restate();
        }
    }
  }

  void _onStart(String sender, WatchStartPacket packet, String me) {
    if (!state.active) {
      _adopt(sender, packet);
      return;
    }
    if (state.hostId == sender) {
      if (state.sessionId == packet.id) {
        // The same showing, said again.
        _takeAnchor(
          packet.seq,
          packet.positionMs,
          packet.playing,
          packet.sentAt,
        );
        return;
      }
      _adopt(sender, packet);
      return;
    }
    // Two people started at once: the lower user id is the host.
    if (state.isHost && sender.compareTo(me) < 0) {
      _adopt(sender, packet);
    }
  }

  void _onSync(String sender, WatchSyncPacket packet) {
    if (!state.active) {
      _askWhatIsOn();
      return;
    }
    if (state.isHost || sender != state.hostId) {
      return;
    }
    if (packet.id != state.sessionId) {
      _askWhatIsOn();
      return;
    }
    _takeAnchor(packet.seq, packet.positionMs, packet.playing, packet.sentAt);
  }

  void _onEnd(String sender, WatchEndPacket packet) {
    if (!state.active ||
        state.isHost ||
        sender != state.hostId ||
        packet.id != state.sessionId) {
      return;
    }
    _deactivate(WatchNotice.hostEnded, name: state.hostName);
  }

  /// Takes where the host says they are, unless the message is older than
  /// one already taken.
  void _takeAnchor(int seq, int positionMs, bool playing, DateTime sentAt) {
    if (seq <= _lastSeq) {
      return;
    }
    _lastSeq = seq;
    final now = _now();
    _heardHostAt = now;
    state = state.copyWith(
      anchor: WatchAnchor.fromPacket(
        positionMs: positionMs,
        playing: playing,
        sentAt: sentAt,
        received: now,
      ),
    );
    _align(force: true);
  }

  void _askWhatIsOn() {
    final now = _now();
    final last = _lastAsk;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _lastAsk = now;
    unawaited(_publish(encodeWatchAsk()));
  }

  /// Takes up [packet] from [sender] as the showing on this device.
  void _adopt(String sender, WatchStartPacket packet) {
    final now = _now();
    final sameHost = state.active && state.hostId == sender;
    _disposePlayer();
    _noticeTimer?.cancel();
    _lastSeq = packet.seq;
    _heardHostAt = now;
    _lastSeek = null;
    _stalls = 0;
    _pendingHostPlay = false;
    final dismissed = sameHost && state.dismissed;
    state = WatchTogetherState(
      active: true,
      sessionId: packet.id,
      hostId: sender,
      link: packet.link,
      title: packet.title.isEmpty ? packet.link.fallbackTitle : packet.title,
      anchor: WatchAnchor.fromPacket(
        positionMs: packet.positionMs,
        playing: packet.playing,
        sentAt: packet.sentAt,
        received: now,
      ),
      dismissed: dismissed,
      muted: state.muted,
      names: state.names,
      playerEpoch: state.playerEpoch,
      callKey: state.callKey,
    );
    _startTicking();
    if (!dismissed && packet.link.synced) {
      _openPlayer();
    }
  }

  /// Stops the showing on this device, with a [notice] for the people who
  /// were watching.
  void _deactivate(WatchNotice notice, {String? name}) {
    _tickTimer?.cancel();
    _tickTimer = null;
    _disposePlayer();
    _heardHostAt = null;
    _lastBeat = null;
    _seq = 0;
    _lastSeq = -1;
    _stalls = 0;
    _pendingHostPlay = false;
    state = WatchTogetherState(
      notice: notice,
      noticeName: name,
      muted: state.muted,
      names: state.names,
      playerEpoch: state.playerEpoch,
      callKey: state.callKey,
    );
    _noticeTimer?.cancel();
    if (notice != WatchNotice.none) {
      _noticeTimer = Timer(const Duration(seconds: 8), clearNotice);
    }
  }
}
