import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/settings/settings_providers.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart' as call_session;
import 'package:wecord/features/voice/watch/watch_player.dart';
import 'package:wecord/features/voice/watch/watch_protocol.dart';
import 'package:wecord/features/voice/watch/watch_sources.dart';
import 'package:wecord/features/voice/watch/watch_sync.dart';

/// Where this device is with loading what the room watches.
enum WatchLoad {
  /// Nothing is being watched.
  idle,

  /// Waiting for this person to say yes (see [WatchConsent]).
  needsConsent,
  loading,
  ready,

  /// The media could not be loaded (a file this person may not open, a link
  /// that is gone, a format this device can not play).
  failed,

  /// This device has no player for the source (YouTube and Bilibili on
  /// iPhone and Mac): the call opens it in the browser and goes by the
  /// host's hints.
  external,
}

/// Why a device waits to be asked before it loads.
enum WatchConsent {
  /// A plain link to a file on another site: loading it tells that site this
  /// device's address, so the host's choice is not enough.
  link,

  /// Audio only (E6) is on to save data and a video would use some.
  dataSaving,
}

/// What a call is watching or listening to together. Lives in memory only:
/// nothing about it is stored anywhere.
@immutable
class WatchState {
  const WatchState({
    this.callKey,
    this.sessionId,
    this.hostId,
    this.authorityId,
    this.source,
    this.title = '',
    this.controlOpen = false,
    this.playing = false,
    this.anchor = Duration.zero,
    this.anchorAt,
    this.startedAt,
    this.load = WatchLoad.idle,
    this.consent,
    this.dismissed = false,
    this.muted = false,
    this.names = const {},
    this.cue,
  });

  /// Which call this is about (conversation / channel / call ids).
  final String? callKey;

  /// Null while nothing is being watched.
  final String? sessionId;

  /// Who started it (a user id): decides who controls, unless
  /// [controlOpen].
  final String? hostId;

  /// Who last moved the playback; their device sends the heartbeat.
  final String? authorityId;
  final WatchSource? source;
  final String title;

  /// Everyone in the call may play, pause and move.
  final bool controlOpen;
  final bool playing;

  /// Where the playback was at [anchorAt] (this device's clock).
  final Duration anchor;
  final DateTime? anchorAt;
  final DateTime? startedAt;
  final WatchLoad load;
  final WatchConsent? consent;

  /// This person stopped watching for themselves; the others go on.
  final bool dismissed;

  /// This person muted it on their own device.
  final bool muted;

  /// Names of everyone seen in the call, by user id.
  final Map<String, String> names;

  /// The latest hint from someone whose player this device can not drive.
  final WatchCueNote? cue;

  bool get active => sessionId != null;

  String? nameOf(String userId) => names[userId];

  WatchState copyWith({
    Object? callKey = _keep,
    Object? sessionId = _keep,
    Object? hostId = _keep,
    Object? authorityId = _keep,
    Object? source = _keep,
    String? title,
    bool? controlOpen,
    bool? playing,
    Duration? anchor,
    Object? anchorAt = _keep,
    Object? startedAt = _keep,
    WatchLoad? load,
    Object? consent = _keep,
    bool? dismissed,
    bool? muted,
    Map<String, String>? names,
    Object? cue = _keep,
  }) {
    return WatchState(
      callKey: identical(callKey, _keep) ? this.callKey : callKey as String?,
      sessionId: identical(sessionId, _keep)
          ? this.sessionId
          : sessionId as String?,
      hostId: identical(hostId, _keep) ? this.hostId : hostId as String?,
      authorityId: identical(authorityId, _keep)
          ? this.authorityId
          : authorityId as String?,
      source: identical(source, _keep) ? this.source : source as WatchSource?,
      title: title ?? this.title,
      controlOpen: controlOpen ?? this.controlOpen,
      playing: playing ?? this.playing,
      anchor: anchor ?? this.anchor,
      anchorAt: identical(anchorAt, _keep)
          ? this.anchorAt
          : anchorAt as DateTime?,
      startedAt: identical(startedAt, _keep)
          ? this.startedAt
          : startedAt as DateTime?,
      load: load ?? this.load,
      consent: identical(consent, _keep)
          ? this.consent
          : consent as WatchConsent?,
      dismissed: dismissed ?? this.dismissed,
      muted: muted ?? this.muted,
      names: names ?? this.names,
      cue: identical(cue, _keep) ? this.cue : cue as WatchCueNote?,
    );
  }
}

const Object _keep = Object();

/// The clock Watch Together uses; tests set their own.
final watchClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Makes a new session id; tests set their own.
final watchSessionIdProvider = Provider<String Function()>((ref) {
  final random = math.Random.secure();
  return () => newWatchSessionId(random.nextInt);
});

/// The watching of the call this device is in (E4).
///
/// How it works: whoever starts it (the host) tells the room *what* is
/// watched (a stored chat file, an address, or a site and a video id) and
/// *where* it is (playing or paused, and the position). Every device loads
/// the media itself and follows: a device that drifts more than a second
/// from the host is moved. Nothing is recorded, uploaded or stored; the
/// media never passes through WeCord or the voice server.
final watchTogetherProvider =
    NotifierProvider<WatchTogetherController, WatchState>(
      WatchTogetherController.new,
    );

class WatchTogetherController extends Notifier<WatchState> {
  late final DateTime Function() _now;
  call_session.VoiceSession? _session;
  StreamSubscription<VoiceDataMessage>? _data;
  final _limits = WatchRateLimits();
  final _gate = WatchSettleGate();
  Timer? _timer;
  WatchPlayer? _player;
  var _generation = 0;
  var _blocked = <String>{};
  DateTime? _lastBeat;
  DateTime? _lastCommandAt;
  DateTime? _lastAnswerAt;
  var _askedForCall = '';

  /// What the UI draws the picture from; null until it is loaded.
  WatchPlayer? get player => state.load == WatchLoad.ready ? _player : null;

  @override
  WatchState build() {
    _now = ref.read(watchClockProvider);
    final session = ref.read(call_session.voiceSessionProvider);
    _session = session;
    final controller = ref.read(call_session.voiceSessionProvider.notifier);
    _data = controller.dataMessages.listen(_onData);
    ref.listen(call_session.voiceSessionProvider, (previous, next) {
      _onSession(next);
    });
    ref.onDispose(() {
      _generation++;
      _timer?.cancel();
      unawaited(_data?.cancel());
      final player = _player;
      _player = null;
      if (player != null) {
        unawaited(player.close());
      }
    });
    final key = _keyOf(session);
    if (key != null) {
      // The controller starts after the call did (the first time its screen
      // is shown): catch up with what is on.
      scheduleMicrotask(() {
        unawaited(_loadBlocked());
        _askAround(key);
      });
    }
    return WatchState(
      callKey: key,
      names: {
        for (final participant in session?.participants ?? const [])
          participant.userId: participant.name,
      },
    );
  }

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

  String? get _myId => _me?.userId;

  VoiceCallParticipant? _participant(String userId) {
    for (final participant in _session?.participants ?? const []) {
      if (participant.userId == userId) {
        return participant;
      }
    }
    return null;
  }

  /// This device may start watching: connected to a call that is not a
  /// stage (where only speakers can send to the room).
  bool get canStart {
    final session = _session;
    return session != null &&
        session.isConnected &&
        !session.stageListener &&
        _me != null;
  }

  bool get isHost => state.active && state.hostId == _myId;

  /// This person may play, pause and move: the host, or anyone while the
  /// host has opened control.
  bool get canControl => state.active && (isHost || state.controlOpen);

  /// This person may end the watching for everyone: the host, and the
  /// people the voice server's signed token marks as moderators.
  bool get canStop => state.active && (isHost || (_me?.captionsHost ?? false));

  void _onSession(call_session.VoiceSession? session) {
    final previous = _session;
    _session = session;
    final key = _keyOf(session);
    if (key != state.callKey) {
      _reset(key);
      if (key == null) {
        return;
      }
      unawaited(_loadBlocked());
      _askAround(key);
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
    final me = _myId;
    if (host != null && host != me && _participant(host) == null) {
      // The person who started it left the call.
      _end();
      return;
    }
    final authority = state.authorityId;
    if (authority != null &&
        authority != host &&
        _participant(authority) == null) {
      state = state.copyWith(authorityId: host);
    }
    if (host == me &&
        previous != null &&
        session.participants.length > previous.participants.length) {
      // Somebody joined: tell them what is on.
      unawaited(_sendStart());
    }
  }

  Future<void> _loadBlocked() async {
    try {
      final blocked = await ref.read(blockedUsersProvider.future);
      _blocked = {for (final profile in blocked) profile.id};
    } on Object {
      _blocked = {};
    }
  }

  /// Asks the call what is on, once per call.
  void _askAround(String key) {
    if (_askedForCall == key) {
      return;
    }
    _askedForCall = key;
    unawaited(_publish(encodeWatchRequest()));
  }

  void _reset(String? key) {
    _teardown();
    _limits.clear();
    _askedForCall = '';
    state = WatchState(callKey: key, names: state.names);
  }

  // ------------------------------------------------------------ starting --

  /// Starts watching [source] with everyone in the call. Only when nothing
  /// is on, or this person is the host (who then changes what is watched).
  /// False when this person may not, or there is no call.
  Future<bool> start(WatchSource source, {String? title}) async {
    if (!canStart || (state.active && !isHost)) {
      return false;
    }
    final me = _myId!;
    final tidy = tidyWatchTitle(title ?? source.label);
    final now = _now();
    _teardown();
    state = state.copyWith(
      sessionId: ref.read(watchSessionIdProvider)(),
      hostId: me,
      authorityId: me,
      source: source,
      title: tidy.isEmpty ? source.label : tidy,
      controlOpen: false,
      playing: false,
      anchor: Duration.zero,
      anchorAt: now,
      startedAt: now,
      load: WatchLoad.loading,
      consent: null,
      dismissed: false,
      cue: null,
    );
    _startTimer();
    await _sendStart();
    unawaited(_loadPlayer());
    return true;
  }

  /// Ends the watching for everyone. For the host and moderators.
  Future<void> stop() async {
    final sid = state.sessionId;
    if (sid == null || !canStop) {
      return;
    }
    await _publish(encodeWatchStop(sid));
    _end();
  }

  /// Stops watching on this device only; the others go on. [rejoin] brings
  /// it back.
  void leaveForMe() {
    if (!state.active || state.dismissed) {
      return;
    }
    _generation++;
    _closePlayer();
    state = state.copyWith(
      dismissed: true,
      load: WatchLoad.idle,
      consent: null,
    );
  }

  /// Watches again after [leaveForMe].
  void rejoin() {
    if (!state.active || !state.dismissed) {
      return;
    }
    state = state.copyWith(dismissed: false);
    _prepareLoad();
  }

  /// The host opens or closes control to everyone in the call.
  Future<void> setControlOpen(bool open) async {
    if (!isHost || open == state.controlOpen) {
      return;
    }
    state = state.copyWith(controlOpen: open);
    await _sendState(withOpen: true);
  }

  /// The person said yes to loading (see [WatchConsent]).
  void acceptConsent() {
    if (state.load != WatchLoad.needsConsent) {
      return;
    }
    state = state.copyWith(consent: null);
    unawaited(_loadPlayer());
  }

  void setMuted(bool muted) {
    if (muted == state.muted) {
      return;
    }
    state = state.copyWith(muted: muted);
    unawaited(_player?.setMuted(muted));
  }

  /// Tries again after a failure.
  void retry() {
    if (state.load == WatchLoad.failed) {
      unawaited(_loadPlayer());
    }
  }

  // ------------------------------------------------------------- control --

  /// Where the playback should be now.
  Duration get expectedPosition {
    return expectedWatchPosition(
      anchor: state.anchor,
      anchorAt: state.anchorAt ?? _now(),
      now: _now(),
      playing: state.playing,
      duration: _player?.duration,
    );
  }

  /// The position to show: the player's, or the expected one while it loads
  /// or when its site gives no time.
  Duration get position {
    final player = _player;
    if (state.load == WatchLoad.ready &&
        player != null &&
        player.remoteControl) {
      return player.position;
    }
    return expectedPosition;
  }

  Duration? get duration =>
      state.load == WatchLoad.ready ? _player?.duration : null;

  /// Plays or pauses for the whole call. For whoever controls.
  Future<void> togglePlay() async {
    if (!canControl || state.load != WatchLoad.ready) {
      return;
    }
    final player = _player;
    final target = !state.playing;
    final at = player != null && player.remoteControl
        ? player.position
        : expectedPosition;
    _setAnchor(at, playing: target, authority: _myId);
    await _driveTo(target, at);
    await _sendState();
  }

  /// Moves the playback for the whole call. For whoever controls.
  Future<void> seekTo(Duration target) async {
    if (!canControl || state.load != WatchLoad.ready) {
      return;
    }
    final length = _player?.duration;
    final clamped = target.isNegative
        ? Duration.zero
        : (length != null && target > length ? length : target);
    _setAnchor(clamped, playing: state.playing, authority: _myId);
    _lastCommandAt = _now();
    _gate.moved(_now());
    await _runPlayer((player) => player.seek(clamped));
    await _sendState();
  }

  /// Tells the call to press play or pause now, for players this device can
  /// not drive (the host or anyone while control is open).
  Future<void> sendCue(WatchCueAction action) async {
    final sid = state.sessionId;
    if (sid == null || !canControl) {
      return;
    }
    state = state.copyWith(
      cue: WatchCueNote(fromId: _myId!, action: action, at: _now()),
    );
    await _publish(encodeWatchCue(sid, action));
  }

  /// Catches up with the call right now (a tap, so the browser lets the
  /// sound play too).
  Future<void> resync() async {
    if (!state.active || state.load != WatchLoad.ready) {
      return;
    }
    _gate.clear();
    await _apply(force: true);
  }

  void _setAnchor(Duration at, {required bool playing, String? authority}) {
    state = state.copyWith(
      anchor: at,
      anchorAt: _now(),
      playing: playing,
      authorityId: authority ?? state.authorityId,
    );
  }

  Future<void> _driveTo(bool playing, Duration at) async {
    _lastCommandAt = _now();
    await _runPlayer((player) async {
      if (!player.remoteControl) {
        return;
      }
      if ((player.position - at).abs() > const Duration(milliseconds: 400)) {
        await player.seek(at);
        _gate.moved(_now());
      }
      if (playing) {
        await player.play();
      } else {
        await player.pause();
      }
    });
  }

  Future<void> _runPlayer(
    Future<void> Function(WatchPlayer player) body,
  ) async {
    final player = _player;
    if (player == null || state.load != WatchLoad.ready) {
      return;
    }
    try {
      await body(player);
    } on Object {
      // The player refused (the browser wants a tap first); the next
      // heartbeat or "catch up" tries again.
    }
  }

  // --------------------------------------------------------------- sending --

  Future<bool> _publish(List<int> data) {
    return ref
        .read(call_session.voiceSessionProvider.notifier)
        .publishData(data, topic: watchTopic);
  }

  Future<void> _sendStart() async {
    final sid = state.sessionId;
    final source = state.source;
    if (sid == null || source == null) {
      return;
    }
    await _publish(
      encodeWatchStart(
        WatchStartPacket(
          sessionId: sid,
          source: source,
          title: state.title,
          controlOpen: state.controlOpen,
          position: position,
          playing: state.playing,
        ),
      ),
    );
  }

  Future<void> _sendState({bool withOpen = false}) async {
    final sid = state.sessionId;
    if (sid == null) {
      return;
    }
    _lastBeat = _now();
    await _publish(
      encodeWatchState(
        WatchStatePacket(
          sessionId: sid,
          position: position,
          playing: state.playing,
          controlOpen: withOpen || isHost ? state.controlOpen : null,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ receiving --

  void _onData(VoiceDataMessage message) {
    if (message.topic != watchTopic) {
      return;
    }
    final session = _session;
    if (session == null || !session.isConnected) {
      return;
    }
    final sender = message.senderId;
    if (sender == _myId ||
        _blocked.contains(sender) ||
        !_limits.allow(sender)) {
      return;
    }
    final packet = decodeWatchPacket(
      message.data,
      conversationId: session.conversationId,
    );
    switch (packet) {
      case null:
        return;
      case WatchStartPacket():
        _onStart(sender, packet);
      case WatchStatePacket():
        _onState(sender, packet);
      case WatchStopPacket():
        _onStop(sender, packet);
      case WatchRequestPacket():
        _onRequest();
      case WatchCuePacket():
        _onCue(sender, packet);
    }
  }

  void _onStart(String sender, WatchStartPacket packet) {
    if (state.active) {
      final mine = state.sessionId;
      if (packet.sessionId == mine) {
        if (sender != state.hostId) {
          return;
        }
        _takeState(packet.position, packet.playing, authority: sender);
        _setOpen(packet.controlOpen);
        return;
      }
      final hostGone =
          state.hostId != _myId && _participant(state.hostId ?? '') == null;
      final fromHost = sender == state.hostId;
      // Two people starting at the same moment: the lower id wins on both
      // devices, so the room settles on one.
      final started = state.startedAt;
      final race =
          isHost &&
          started != null &&
          _now().difference(started) < const Duration(seconds: 5) &&
          packet.sessionId.compareTo(mine ?? '') < 0;
      if (!fromHost && !hostGone && !race) {
        return;
      }
    }
    _adopt(sender, packet);
  }

  void _adopt(String host, WatchStartPacket packet) {
    final session = _session;
    _teardown();
    final needsConsent = packet.source is WatchLinkSource
        ? WatchConsent.link
        : (session?.audioOnly == true && !packet.source.isAudio
              ? WatchConsent.dataSaving
              : null);
    state = state.copyWith(
      sessionId: packet.sessionId,
      hostId: host,
      authorityId: host,
      source: packet.source,
      title: packet.title,
      controlOpen: packet.controlOpen,
      playing: packet.playing,
      anchor: packet.position,
      anchorAt: _now(),
      startedAt: _now(),
      load: needsConsent != null ? WatchLoad.needsConsent : WatchLoad.loading,
      consent: needsConsent,
      dismissed: false,
      cue: null,
    );
    _startTimer();
    if (needsConsent == null) {
      unawaited(_loadPlayer());
    }
  }

  void _onState(String sender, WatchStatePacket packet) {
    if (packet.sessionId != state.sessionId) {
      return;
    }
    final fromHost = sender == state.hostId;
    if (!fromHost && !state.controlOpen) {
      return;
    }
    if (fromHost && packet.controlOpen != null) {
      _setOpen(packet.controlOpen!);
    }
    // Control opened by the host is read first, so a controller's packet
    // that arrives right after is accepted.
    _takeState(packet.position, packet.playing, authority: sender);
  }

  void _setOpen(bool open) {
    if (open != state.controlOpen) {
      state = state.copyWith(controlOpen: open);
    }
  }

  void _takeState(
    Duration position,
    bool playing, {
    required String authority,
  }) {
    _setAnchor(position, playing: playing, authority: authority);
    unawaited(_apply());
  }

  void _onStop(String sender, WatchStopPacket packet) {
    if (packet.sessionId != state.sessionId) {
      return;
    }
    final moderator = _participant(sender)?.captionsHost ?? false;
    if (sender == state.hostId || moderator) {
      _end();
    }
  }

  void _onRequest() {
    if (!isHost) {
      return;
    }
    final now = _now();
    final last = _lastAnswerAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastAnswerAt = now;
    unawaited(_sendStart());
  }

  void _onCue(String sender, WatchCuePacket packet) {
    if (packet.sessionId != state.sessionId) {
      return;
    }
    if (sender != state.hostId && !state.controlOpen) {
      return;
    }
    state = state.copyWith(
      cue: WatchCueNote(fromId: sender, action: packet.action, at: _now()),
    );
  }

  // --------------------------------------------------------------- playing --

  /// Loads the player unless the person must say yes first.
  void _prepareLoad() {
    final source = state.source;
    if (source == null) {
      return;
    }
    final consent = !isHost && source is WatchLinkSource
        ? WatchConsent.link
        : null;
    if (consent != null) {
      state = state.copyWith(load: WatchLoad.needsConsent, consent: consent);
      return;
    }
    unawaited(_loadPlayer());
  }

  Future<void> _loadPlayer() async {
    final source = state.source;
    final session = _session;
    if (source == null || session == null || state.dismissed) {
      return;
    }
    final attempt = ++_generation;
    _closePlayer();
    state = state.copyWith(load: WatchLoad.loading, consent: null);
    WatchPlayer? player;
    try {
      player = await ref.read(watchPlayerFactoryProvider)(
        source,
        conversationId: session.conversationId,
      );
    } on Object {
      if (attempt == _generation && state.active) {
        state = state.copyWith(load: WatchLoad.failed);
      }
      return;
    }
    if (attempt != _generation || !state.active || state.dismissed) {
      unawaited(player?.close());
      return;
    }
    if (player == null) {
      state = state.copyWith(load: WatchLoad.external);
      return;
    }
    _player = player;
    _gate.clear();
    if (state.muted) {
      unawaited(player.setMuted(true));
    }
    state = state.copyWith(load: WatchLoad.ready);
    await _apply(force: true);
  }

  void _closePlayer() {
    final player = _player;
    _player = null;
    if (player != null) {
      unawaited(player.close());
    }
  }

  void _teardown() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _closePlayer();
    _gate.clear();
    _lastBeat = null;
    _lastCommandAt = null;
  }

  void _end() {
    _teardown();
    state = WatchState(callKey: state.callKey, names: state.names);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Makes this device's player follow the agreed playback: plays or
  /// pauses it, and moves it when it is more than a second off.
  Future<void> _apply({bool force = false}) async {
    final player = _player;
    if (player == null ||
        state.load != WatchLoad.ready ||
        !player.remoteControl) {
      return;
    }
    final now = _now();
    final expected = expectedPosition;
    try {
      final correction = watchCorrection(
        expected: expected,
        actual: player.position,
        playing: state.playing,
      );
      if (correction != null &&
          (force || (_gate.isSettled(now) && !player.isBuffering))) {
        _gate.moved(now);
        await player.seek(correction);
      }
      if (state.playing && !player.hasEnded) {
        if (!player.isPlaying) {
          _lastCommandAt = now;
          await player.play();
        }
      } else if (player.isPlaying) {
        _lastCommandAt = now;
        await player.pause();
      }
    } on Object {
      // The player is busy or the browser wants a tap; the next beat tries.
    }
  }

  void _tick() {
    if (!state.active || _session?.isConnected != true) {
      return;
    }
    final player = _player;
    final now = _now();
    final authority = state.authorityId == _myId;
    if (authority &&
        player != null &&
        state.load == WatchLoad.ready &&
        player.remoteControl) {
      // The one in charge goes by their own player: if it stopped (the
      // video ended, a phone call took the sound) the room follows.
      final settled =
          _lastCommandAt == null ||
          now.difference(_lastCommandAt!) > const Duration(seconds: 2);
      if (settled && !player.isBuffering) {
        if (player.hasEnded && state.playing) {
          _setAnchor(player.position, playing: false);
          unawaited(_sendState());
          return;
        }
        if (player.isPlaying != state.playing && !player.hasEnded) {
          _setAnchor(player.position, playing: player.isPlaying);
          unawaited(_sendState());
          return;
        }
      }
    } else if (!authority) {
      unawaited(_apply());
    }
    if (authority) {
      final last = _lastBeat;
      final every = state.playing ? watchPlayingBeat : watchPausedBeat;
      if (last == null || now.difference(last) >= every) {
        if (state.playing && player != null && player.remoteControl) {
          _setAnchor(player.position, playing: true);
        }
        unawaited(_sendState());
      }
    }
    // A cue is a hint, not a notice that stays.
    final cue = state.cue;
    if (cue != null && now.difference(cue.at) > const Duration(seconds: 12)) {
      state = state.copyWith(cue: null);
    }
  }
}
