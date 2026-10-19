import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/captions/caption_listener.dart';
import 'package:wecord/features/voice/captions/caption_protocol.dart';
import 'package:wecord/features/voice/captions/caption_segmenter.dart';
import 'package:wecord/features/voice/voice_call.dart';
import 'package:wecord/features/voice/voice_session.dart' as call_session;
import 'package:wecord/features/voice_input/voice_input_controller.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/features/voice_input/voice_recognizer.dart';

/// What this device is doing for the captions.
enum CaptionMic {
  /// Not listening: captions are off, or this person does not share theirs.
  off,
  starting,
  listening,

  /// Not listening because the microphone in the call is off (muted,
  /// deafened, push to talk not held) or voice input is using the
  /// recognizer.
  paused,

  /// This device (or browser) can not make captions in this language.
  unsupported,

  /// Speech recognition or the microphone is not allowed for the app.
  denied,

  /// The platform's recognizer sends audio to its service: ask first.
  needsConsent,
}

/// The most settled lines kept in memory.
const maxCaptionLines = 3000;

/// The captions of the call this device is in. Lives in memory only.
@immutable
class CaptionsState {
  const CaptionsState({
    this.active = false,
    this.hostId,
    this.startedAt,
    this.sharing = true,
    this.mic = CaptionMic.off,
    this.engine = VoiceInputEngine.onDevice,
    this.language = VoiceInputLanguage.english,
    this.lines = const [],
    this.live = const {},
    this.unsupported = const {},
    this.names = const {},
    this.hidden = false,
    this.callKey,
  });

  /// Captions are on in this call.
  final bool active;

  /// Who turned them on (a user id).
  final String? hostId;
  final DateTime? startedAt;

  /// This person shares their own captions with the call.
  final bool sharing;
  final CaptionMic mic;

  /// Where this device's recognizer runs, for the consent text.
  final VoiceInputEngine engine;
  final VoiceInputLanguage language;

  /// Settled lines, oldest first (from everyone who shares).
  final List<CaptionLine> lines;

  /// The line each person is saying right now, by user id.
  final Map<String, CaptionLine> live;

  /// People whose devices can not make captions.
  final Set<String> unsupported;

  /// Names of everyone seen in the call, by user id.
  final Map<String, String> names;

  /// This person hides the caption bar on their own screen. Captions stay
  /// on for the call, and they can still share theirs.
  final bool hidden;

  /// Which call this is about (conversation / channel / call ids).
  final String? callKey;

  CaptionsState copyWith({
    bool? active,
    Object? hostId = _keep,
    Object? startedAt = _keep,
    bool? sharing,
    CaptionMic? mic,
    VoiceInputEngine? engine,
    VoiceInputLanguage? language,
    List<CaptionLine>? lines,
    Map<String, CaptionLine>? live,
    Set<String>? unsupported,
    Map<String, String>? names,
    bool? hidden,
    Object? callKey = _keep,
  }) {
    return CaptionsState(
      active: active ?? this.active,
      hostId: identical(hostId, _keep) ? this.hostId : hostId as String?,
      startedAt: identical(startedAt, _keep)
          ? this.startedAt
          : startedAt as DateTime?,
      sharing: sharing ?? this.sharing,
      mic: mic ?? this.mic,
      engine: engine ?? this.engine,
      language: language ?? this.language,
      lines: lines ?? this.lines,
      live: live ?? this.live,
      unsupported: unsupported ?? this.unsupported,
      names: names ?? this.names,
      hidden: hidden ?? this.hidden,
      callKey: identical(callKey, _keep) ? this.callKey : callKey as String?,
    );
  }

  /// A person's name, or null when not known.
  String? nameOf(String userId) => names[userId];
}

const Object _keep = Object();

/// What the host keeps when captions end: the words, to write the recap
/// from. Never stored anywhere.
@immutable
class CaptionTranscript {
  const CaptionTranscript({
    required this.lines,
    required this.startedAt,
    required this.names,
    required this.conversationId,
    this.circleId,
  });

  final List<CaptionLine> lines;
  final DateTime startedAt;
  final Map<String, String> names;
  final String conversationId;
  final String? circleId;

  bool get isEmpty => lines.isEmpty;

  /// How many different people said something.
  int get speakerCount => {for (final line in lines) line.speakerId}.length;

  /// The sentences as the `ai` function reads them: who (user id), what, and
  /// how many seconds after captions started.
  List<Map<String, Object>> toRequestEntries() {
    return [
      for (final line in lines)
        {
          'speaker': line.speakerId,
          'text': line.text,
          'at': line.at.difference(startedAt).inSeconds.clamp(0, 172800),
        },
    ];
  }
}

/// The clock captions use for times and pauses; tests set their own.
final captionClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// A call's captions (E1).
///
/// How it works: whoever may (see [VoiceCallParticipant.captionsHost]) turns
/// captions on, which tells the room. Then every person who shares their
/// captions has their own device recognize their own microphone and sends the
/// sentences to the room as small data messages; everybody puts the
/// sentences together. Nothing is recorded and no audio leaves the device by
/// this feature; the words live in memory until the call ends, unless the
/// host writes the recap.
final captionsProvider = NotifierProvider<CaptionsController, CaptionsState>(
  CaptionsController.new,
);

class CaptionsController extends Notifier<CaptionsState> {
  late final DateTime Function() _now;
  call_session.VoiceSession? _session;
  StreamSubscription<VoiceDataMessage>? _data;
  CaptionListener? _listener;
  Timer? _beat;
  final _limits = CaptionRateLimits();
  DateTime? _heardHostAt;
  var _lineId = 0;
  DateTime? _lastPartialSent;
  String _lastPartialText = '';
  var _serverAllowed = false;
  var _dictating = false;
  var _announcedUnsupported = false;
  var _generation = 0;

  @override
  CaptionsState build() {
    _now = ref.read(captionClockProvider);
    final controller = ref.read(call_session.voiceSessionProvider.notifier);
    _data = controller.dataMessages.listen(_onData);
    ref.listen(call_session.voiceSessionProvider, (previous, next) {
      _onSession(next);
    });
    ref.listen(voiceInputProvider.select((input) => input.isActive), (
      previous,
      next,
    ) {
      _dictating = next;
      _syncListening();
    });
    ref.onDispose(() {
      _generation++;
      unawaited(_data?.cancel());
      _beat?.cancel();
      _listener?.dispose();
    });
    final session = ref.read(call_session.voiceSessionProvider);
    _session = session;
    return CaptionsState(
      language: VoiceInputLanguage.ofApp,
      callKey: _keyOf(session),
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

  VoiceCallParticipant? _participant(String userId) {
    for (final participant in _session?.participants ?? const []) {
      if (participant.userId == userId) {
        return participant;
      }
    }
    return null;
  }

  /// This person may turn captions on in this call.
  bool get canHost => _me?.captionsHost ?? false;

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
    if (state.active) {
      final host = state.hostId;
      final me = _me?.userId;
      if (host != null && host != me && _participant(host) == null) {
        // The person who turned captions on left the call.
        _deactivate();
        return;
      }
      if (host == me &&
          previous != null &&
          session.participants.length > previous.participants.length) {
        // Somebody joined: tell them captions are on.
        unawaited(_sendControl(on: true));
      }
    }
    _syncListening();
  }

  void _reset(String? key) {
    _generation++;
    _beat?.cancel();
    _beat = null;
    final listener = _listener;
    _listener = null;
    listener?.dispose();
    _limits.clear();
    _lineId = 0;
    _heardHostAt = null;
    _lastPartialText = '';
    _lastPartialSent = null;
    _announcedUnsupported = false;
    state = CaptionsState(
      language: state.language,
      sharing: true,
      callKey: key,
    );
  }

  // ------------------------------------------------------- host actions --

  /// Turns captions on for the whole call. Only for someone the voice server
  /// says may (the call's starter, a moderator).
  Future<void> start() async {
    if (state.active || !canHost || _session?.isConnected != true) {
      return;
    }
    final me = _me!.userId;
    _activate(me);
    await _sendControl(on: true);
    _syncListening();
  }

  /// Turns captions off for everyone and returns the words, for a recap.
  /// Only for someone the voice server says may.
  Future<CaptionTranscript?> stop() async {
    if (!state.active || !canHost) {
      return null;
    }
    // A listener that is mid-sentence settles it first.
    final listener = _listener;
    _listener = null;
    if (listener != null) {
      await listener.stop();
    }
    final transcript = _transcript(_session);
    await _sendControl(on: false);
    _deactivate();
    return transcript;
  }

  /// Hides (or shows) the caption bar on this screen only.
  void setHidden(bool hidden) {
    if (hidden != state.hidden) {
      state = state.copyWith(hidden: hidden);
    }
  }

  CaptionTranscript? _transcript(call_session.VoiceSession? session) {
    final started = state.startedAt;
    if (session == null || started == null) {
      return null;
    }
    return CaptionTranscript(
      lines: List.of(state.lines),
      startedAt: started,
      names: Map.of(state.names),
      conversationId: session.conversationId,
      circleId: session.circleId,
    );
  }

  void _activate(String hostId) {
    _heardHostAt = _now();
    state = state.copyWith(
      active: true,
      hostId: hostId,
      startedAt: state.startedAt ?? _now(),
      lines: const [],
      live: const {},
    );
    _beat?.cancel();
    _beat = Timer.periodic(const Duration(seconds: 5), (_) => _heartbeat());
  }

  void _deactivate() {
    _generation++;
    _beat?.cancel();
    _beat = null;
    final listener = _listener;
    _listener = null;
    listener?.dispose();
    _lineId = 0;
    _heardHostAt = null;
    _lastPartialText = '';
    _announcedUnsupported = false;
    state = CaptionsState(
      language: state.language,
      sharing: state.sharing,
      names: state.names,
      callKey: state.callKey,
    );
  }

  DateTime? _lastBeat;

  void _heartbeat() {
    final now = _now();
    final me = _me?.userId;
    if (state.hostId == me) {
      final last = _lastBeat;
      if (last == null || now.difference(last) >= captionHeartbeat) {
        _lastBeat = now;
        unawaited(_sendControl(on: true));
      }
      return;
    }
    final heard = _heardHostAt;
    if (heard != null && now.difference(heard) > captionHostTimeout) {
      _deactivate();
    }
  }

  Future<void> _sendControl({required bool on}) async {
    _lastBeat = _now();
    await ref
        .read(call_session.voiceSessionProvider.notifier)
        .publishData(encodeCaptionControl(on: on), topic: captionTopic);
  }

  // ------------------------------------------------------- my own choice --

  /// Shares this person's own captions, or stops (they still see everyone
  /// else's).
  Future<void> setSharing(bool sharing) async {
    if (sharing == state.sharing) {
      return;
    }
    state = state.copyWith(sharing: sharing);
    if (!sharing) {
      // What was half said is not sent.
      final me = _me?.userId;
      if (me != null && state.live.containsKey(me)) {
        state = state.copyWith(live: {...state.live}..remove(me));
      }
    }
    _syncListening();
  }

  Future<void> setLanguage(VoiceInputLanguage language) async {
    if (language == state.language) {
      return;
    }
    state = state.copyWith(language: language);
    final listener = _listener;
    _listener = null;
    listener?.dispose();
    _announcedUnsupported = false;
    _syncListening();
  }

  /// The person agreed to the platform's speech service hearing them.
  Future<void> allowServer() async {
    _serverAllowed = true;
    if (state.engine == VoiceInputEngine.browser) {
      try {
        await ref.read(voiceInputStoreProvider).saveBrowserConsent();
      } on Object {
        // Asked again next time.
      }
    }
    if (state.mic == CaptionMic.needsConsent) {
      state = state.copyWith(mic: CaptionMic.off);
    }
    _syncListening();
  }

  /// Tries again after a problem.
  void retry() {
    if (state.mic == CaptionMic.unsupported || state.mic == CaptionMic.denied) {
      state = state.copyWith(mic: CaptionMic.off);
      _syncListening();
    }
  }

  // ------------------------------------------------- this device listens --

  bool get _micOpen {
    final session = _session;
    return session != null && session.isConnected && session.microphoneWanted;
  }

  bool get _wantListening =>
      state.active && state.sharing && _micOpen && !_dictating;

  void _syncListening() {
    if (!ref.mounted) {
      return;
    }
    if (!state.active || !state.sharing) {
      final listener = _listener;
      if (listener != null) {
        _listener = null;
        unawaited(listener.stop());
      }
      if (state.mic != CaptionMic.off && state.mic != CaptionMic.unsupported) {
        state = state.copyWith(mic: CaptionMic.off);
      }
      return;
    }
    if (!_wantListening) {
      final listener = _listener;
      if (listener != null) {
        _listener = null;
        unawaited(listener.stop());
      }
      if (state.mic == CaptionMic.listening ||
          state.mic == CaptionMic.starting ||
          state.mic == CaptionMic.off) {
        state = state.copyWith(mic: CaptionMic.paused);
      }
      return;
    }
    if (_listener != null) {
      return;
    }
    if (state.mic == CaptionMic.unsupported ||
        state.mic == CaptionMic.denied ||
        state.mic == CaptionMic.needsConsent) {
      return;
    }
    unawaited(_beginListening());
  }

  Future<void> _beginListening() async {
    final generation = ++_generation;
    state = state.copyWith(mic: CaptionMic.starting);
    final recognizer = ref.read(voiceRecognizerProvider);
    final locale = state.language.locale;
    final VoiceInputCapabilities capabilities;
    try {
      capabilities = await recognizer.capabilities(locale);
    } on Object {
      return _cannotListen(generation, CaptionMic.unsupported);
    }
    if (generation != _generation || !ref.mounted) {
      return;
    }
    if (!capabilities.usable) {
      return _cannotListen(generation, CaptionMic.unsupported);
    }
    state = state.copyWith(engine: capabilities.engine);
    final needsConsent = switch (capabilities.engine) {
      VoiceInputEngine.onDevice => false,
      VoiceInputEngine.appleServer => !_serverAllowed,
      VoiceInputEngine.browser =>
        !_serverAllowed &&
            !await ref.read(voiceInputStoreProvider).loadBrowserConsent(),
    };
    if (generation != _generation || !ref.mounted) {
      return;
    }
    if (needsConsent) {
      state = state.copyWith(mic: CaptionMic.needsConsent);
      return;
    }
    final listener = CaptionListener(
      recognizer: recognizer,
      now: _now,
      onSegment: (segment) => _heard(generation, segment),
      onFailure: (failure, {needsServer = false}) =>
          _failed(generation, failure, needsServer: needsServer),
    );
    _listener = listener;
    await listener.start(
      locale: locale,
      allowServer: capabilities.engine != VoiceInputEngine.onDevice,
    );
    if (generation != _generation || !ref.mounted || _listener != listener) {
      return;
    }
    if (listener.isListening) {
      state = state.copyWith(mic: CaptionMic.listening);
      if (_announcedUnsupported) {
        _announcedUnsupported = false;
        unawaited(
          ref
              .read(call_session.voiceSessionProvider.notifier)
              .publishData(
                encodeCaptionSupport(supported: true),
                topic: captionTopic,
              ),
        );
      }
    }
  }

  void _failed(
    int generation,
    VoiceInputFailure failure, {
    bool needsServer = false,
  }) {
    if (generation != _generation || !ref.mounted) {
      return;
    }
    _listener = null;
    if (needsServer) {
      state = state.copyWith(
        mic: CaptionMic.needsConsent,
        engine: VoiceInputEngine.appleServer,
      );
      return;
    }
    switch (failure) {
      case VoiceInputFailure.speechDenied || VoiceInputFailure.micDenied:
        _cannotListen(generation, CaptionMic.denied);
      case VoiceInputFailure.noSpeech:
        state = state.copyWith(mic: CaptionMic.paused);
        _syncListening();
      case VoiceInputFailure.unsupportedLanguage ||
          VoiceInputFailure.unavailable ||
          VoiceInputFailure.failed:
        _cannotListen(generation, CaptionMic.unsupported);
    }
  }

  void _cannotListen(int generation, CaptionMic mic) {
    if (generation != _generation || !ref.mounted) {
      return;
    }
    state = state.copyWith(mic: mic);
    if (!_announcedUnsupported) {
      _announcedUnsupported = true;
      unawaited(
        ref
            .read(call_session.voiceSessionProvider.notifier)
            .publishData(
              encodeCaptionSupport(supported: false),
              topic: captionTopic,
            ),
      );
    }
  }

  /// Something this person said.
  void _heard(int generation, CaptionSegment segment) {
    if (generation != _generation || !ref.mounted) {
      return;
    }
    final me = _me?.userId;
    if (me == null || !state.active || !state.sharing) {
      return;
    }
    final now = _now();
    final controller = ref.read(call_session.voiceSessionProvider.notifier);
    if (segment.isFinal) {
      final line = CaptionLine(
        speakerId: me,
        id: _lineId,
        text: segment.text,
        at: now,
      );
      _lineId++;
      _lastPartialText = '';
      state = state.copyWith(
        lines: _append(state.lines, line),
        live: {...state.live}..remove(me),
      );
      unawaited(
        controller.publishData(
          encodeCaptionLine(
            id: line.id,
            text: line.text,
            at: now,
            isFinal: true,
          ),
          topic: captionTopic,
        ),
      );
      return;
    }
    state = state.copyWith(
      live: {
        ...state.live,
        me: CaptionLine(
          speakerId: me,
          id: _lineId,
          text: segment.text,
          at: now,
          isFinal: false,
        ),
      },
    );
    final last = _lastPartialSent;
    if (segment.text != _lastPartialText &&
        (last == null ||
            now.difference(last) >= const Duration(milliseconds: 500))) {
      _lastPartialSent = now;
      _lastPartialText = segment.text;
      unawaited(
        controller.publishData(
          encodeCaptionLine(
            id: _lineId,
            text: segment.text,
            at: now,
            isFinal: false,
          ),
          topic: captionTopic,
          reliable: false,
        ),
      );
    }
  }

  List<CaptionLine> _append(List<CaptionLine> lines, CaptionLine line) {
    final next = [...lines, line];
    if (next.length > maxCaptionLines) {
      next.removeRange(0, next.length - maxCaptionLines);
    }
    return next;
  }

  // ----------------------------------------------------- what others send --

  void _onData(VoiceDataMessage message) {
    if (message.topic != captionTopic || !ref.mounted) {
      return;
    }
    // Only people in the room count, as the voice server sees it.
    final sender = _participant(message.senderId);
    if (sender == null || sender.isLocal) {
      return;
    }
    if (!_limits.allow(message.senderId)) {
      return;
    }
    final packet = decodeCaptionPacket(message.data);
    if (packet == null) {
      return;
    }
    switch (packet) {
      case CaptionControl(:final on):
        // Only someone the voice server says may turn captions on can.
        if (!sender.captionsHost) {
          return;
        }
        if (on) {
          if (state.active) {
            if (state.hostId == sender.userId) {
              _heardHostAt = _now();
            }
          } else {
            _activate(sender.userId);
            _syncListening();
          }
        } else if (state.active) {
          _deactivate();
        }
      case CaptionSupportPacket(:final supported):
        final set = {...state.unsupported};
        if (supported) {
          set.remove(sender.userId);
        } else {
          set.add(sender.userId);
        }
        state = state.copyWith(unsupported: set);
      case CaptionLinePacket():
        if (!state.active) {
          return;
        }
        final at = clampCaptionTime(packet.at, _now());
        final line = CaptionLine(
          speakerId: sender.userId,
          id: packet.id,
          text: packet.text,
          at: at,
          isFinal: packet.isFinal,
        );
        if (packet.isFinal) {
          final live = {...state.live};
          final current = live[sender.userId];
          if (current != null && current.id <= packet.id) {
            live.remove(sender.userId);
          }
          state = state.copyWith(
            lines: _append(state.lines, line),
            live: live,
            unsupported: state.unsupported.contains(sender.userId)
                ? ({...state.unsupported}..remove(sender.userId))
                : null,
          );
        } else {
          final current = state.live[sender.userId];
          if (current != null && current.id > packet.id) {
            return;
          }
          state = state.copyWith(live: {...state.live, sender.userId: line});
        }
    }
  }
}

/// Whether the voice server's token lets this person turn captions on in
/// the call they are in.
final captionsCanHostProvider = Provider<bool>((ref) {
  final session = ref.watch(call_session.voiceSessionProvider);
  if (session == null || !session.isConnected) {
    return false;
  }
  for (final participant in session.participants) {
    if (participant.isLocal) {
      return participant.captionsHost;
    }
  }
  return false;
});
