import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/features/transcribe/voice_transcriber.dart';

enum TranscriptPhase {
  /// Getting the audio and recognizing it.
  loading,

  /// The language can't be recognized on the device: waiting for the person
  /// to agree to send the audio to Apple's speech service.
  needsConsent,

  done,
  failed,

  /// Can't be transcribed here at all ([TranscriptState.unavailable] says
  /// why).
  unavailable,
}

/// The transcript shown under one voice message.
@immutable
class TranscriptState {
  const TranscriptState({
    required this.phase,
    this.text,
    this.engine,
    this.error,
    this.unavailable,
  });

  final TranscriptPhase phase;
  final String? text;
  final TranscribeEngine? engine;
  final Object? error;
  final TranscribeUnavailable? unavailable;
}

/// Transcripts of voice messages, shown under the message until hidden. A
/// transcript is kept on this device (see [TranscriptCache]) so showing it
/// again costs nothing, and is never stored on the server.
final transcriptsProvider =
    NotifierProvider<TranscriptController, Map<String, TranscriptState>>(
      TranscriptController.new,
    );

class TranscriptController extends Notifier<Map<String, TranscriptState>> {
  final _generations = <String, int>{};

  /// Messages whose transcript the person hid: automatic transcription
  /// leaves them alone for the rest of the session.
  final _hidden = <String>{};

  /// Automatic transcriptions run one after another.
  var _queue = Future<void>.value();

  @override
  Map<String, TranscriptState> build() {
    // A different person signing in starts with nothing shown.
    ref.watch(transcriptUserIdProvider);
    _generations.clear();
    _hidden.clear();
    return const {};
  }

  /// Whether [messageId] shows a transcript (or is getting one).
  bool isShown(String messageId) => state.containsKey(messageId);

  int _next(String messageId) {
    final generation = (_generations[messageId] ?? 0) + 1;
    _generations[messageId] = generation;
    return generation;
  }

  bool _current(String messageId, int generation) =>
      ref.mounted && _generations[messageId] == generation;

  void _show(String messageId, int generation, TranscriptState value) {
    if (_current(messageId, generation)) {
      state = {...state, messageId: value};
    }
  }

  Future<CachedTranscript?> _cached(String messageId) async {
    try {
      return await ref.read(transcriptCacheProvider).read(messageId);
    } on Object {
      return null;
    }
  }

  /// Shows the transcript of [request]: the saved one when there is one,
  /// otherwise it is made now. With [allowServerRecognition] a language the
  /// device can't recognize alone goes to Apple's servers (the person said
  /// so); without it they are asked first.
  Future<void> show(
    TranscribeRequest request, {
    bool allowServerRecognition = false,
  }) async {
    final id = request.messageId;
    final generation = _next(id);
    _hidden.remove(id);
    final cached = await _cached(id);
    if (!_current(id, generation)) {
      return;
    }
    if (cached != null) {
      _show(
        id,
        generation,
        TranscriptState(
          phase: TranscriptPhase.done,
          text: cached.text,
          engine: cached.engine,
        ),
      );
      return;
    }
    _show(
      id,
      generation,
      const TranscriptState(phase: TranscriptPhase.loading),
    );
    await _plan(
      request,
      generation,
      allowServerRecognition: allowServerRecognition,
    );
  }

  Future<void> _plan(
    TranscribeRequest request,
    int generation, {
    required bool allowServerRecognition,
    bool automatic = false,
  }) async {
    final id = request.messageId;
    final transcriber = ref.read(voiceTranscriberProvider);
    final TranscribePlan plan;
    try {
      plan = await transcriber.plan(request);
    } on Object catch (error) {
      _show(
        id,
        generation,
        TranscriptState(phase: TranscriptPhase.failed, error: error),
      );
      return;
    }
    if (!_current(id, generation)) {
      return;
    }
    final engine = plan.engine;
    if (engine == null) {
      _show(
        id,
        generation,
        TranscriptState(
          phase: TranscriptPhase.unavailable,
          unavailable: plan.unavailable,
        ),
      );
      return;
    }
    if (automatic &&
        !(engine == TranscribeEngine.onDevice && plan.canAutoStart)) {
      // Never on its own through a server, or without permission.
      return;
    }
    if (engine == TranscribeEngine.aiServer && !ref.read(aiEnabledProvider)) {
      _show(
        id,
        generation,
        const TranscriptState(
          phase: TranscriptPhase.unavailable,
          unavailable: TranscribeUnavailable.aiOff,
        ),
      );
      return;
    }
    if (engine == TranscribeEngine.appleServer && !allowServerRecognition) {
      _show(
        id,
        generation,
        const TranscriptState(phase: TranscriptPhase.needsConsent),
      );
      return;
    }
    await _run(
      request,
      generation,
      allowServerRecognition: allowServerRecognition,
      automatic: automatic,
    );
  }

  Future<void> _run(
    TranscribeRequest request,
    int generation, {
    required bool allowServerRecognition,
    bool automatic = false,
  }) async {
    final id = request.messageId;
    _show(
      id,
      generation,
      const TranscriptState(phase: TranscriptPhase.loading),
    );
    // A failure of a transcription nobody asked for just leaves the message
    // as it was.
    void fail(Object error) {
      if (!_current(id, generation)) {
        return;
      }
      if (automatic) {
        state = {...state}..remove(id);
      } else {
        _show(
          id,
          generation,
          TranscriptState(phase: TranscriptPhase.failed, error: error),
        );
      }
    }

    try {
      final transcript = await ref
          .read(voiceTranscriberProvider)
          .transcribe(request, allowServerRecognition: allowServerRecognition);
      if (!_current(id, generation)) {
        return;
      }
      _show(
        id,
        generation,
        TranscriptState(
          phase: TranscriptPhase.done,
          text: transcript.text,
          engine: transcript.engine,
        ),
      );
      try {
        await ref
            .read(transcriptCacheProvider)
            .write(
              id,
              CachedTranscript(
                text: transcript.text,
                engine: transcript.engine,
                savedAt: DateTime.now().toUtc(),
              ),
            );
      } on Object {
        // Still shown; it is made again next time.
      }
    } on TranscribeException catch (error) {
      if (error.kind == TranscribeFailureKind.needsServer && !automatic) {
        _show(
          id,
          generation,
          const TranscriptState(phase: TranscriptPhase.needsConsent),
        );
      } else {
        fail(error);
      }
    } on Object catch (error) {
      if (error is AiNotConfiguredException ||
          error is AiTranscribeNotConfiguredException) {
        ref.invalidate(aiStatusProvider);
      }
      fail(error);
    }
  }

  /// The person agreed to send this audio to Apple's speech service.
  Future<void> confirmServerRecognition(TranscribeRequest request) =>
      show(request, allowServerRecognition: true);

  /// Hides the transcript. The saved one stays, so showing it again is
  /// instant.
  void hide(String messageId) {
    _next(messageId);
    _hidden.add(messageId);
    if (state.containsKey(messageId)) {
      state = {...state}..remove(messageId);
    }
  }

  /// Settings → AI → Auto-transcribe: shows a saved transcript, or makes one
  /// on the device when the voice message is on screen. Never through a
  /// server, never again for one the person hid, and one at a time.
  void autoTranscribe(TranscribeRequest request) {
    final id = request.messageId;
    if (_hidden.contains(id) || state.containsKey(id)) {
      return;
    }
    final generation = _next(id);
    _queue = _queue
        .then((_) async {
          if (!_current(id, generation) || !ref.read(autoTranscribeProvider)) {
            return;
          }
          final cached = await _cached(id);
          if (!_current(id, generation)) {
            return;
          }
          if (cached != null) {
            _show(
              id,
              generation,
              TranscriptState(
                phase: TranscriptPhase.done,
                text: cached.text,
                engine: cached.engine,
              ),
            );
            return;
          }
          await _plan(
            request,
            generation,
            allowServerRecognition: false,
            automatic: true,
          );
        })
        .catchError((Object _) {});
  }
}

/// Where the Auto-transcribe switch is kept; tests swap in memory.
abstract interface class AutoTranscribeStore {
  Future<bool?> load();

  Future<void> save(bool enabled);
}

const _autoTranscribeKey = 'wecord.transcribe.auto';

class SharedPreferencesAutoTranscribeStore implements AutoTranscribeStore {
  const SharedPreferencesAutoTranscribeStore();

  @override
  Future<bool?> load() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_autoTranscribeKey);
  }

  @override
  Future<void> save(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoTranscribeKey, enabled);
  }
}

class InMemoryAutoTranscribeStore implements AutoTranscribeStore {
  InMemoryAutoTranscribeStore([this._enabled]);

  bool? _enabled;

  @override
  Future<bool?> load() async => _enabled;

  @override
  Future<void> save(bool enabled) async => _enabled = enabled;
}

final autoTranscribeStoreProvider = Provider<AutoTranscribeStore>(
  (ref) => const SharedPreferencesAutoTranscribeStore(),
);

/// Settings → AI → "Auto-transcribe voice messages": off unless the person
/// turns it on, and kept on this device. When on, voice messages in the open
/// chat transcribe themselves on the device, never through the server.
final autoTranscribeProvider = NotifierProvider<AutoTranscribeController, bool>(
  AutoTranscribeController.new,
);

class AutoTranscribeController extends Notifier<bool> {
  var _changed = false;

  @override
  bool build() {
    ref.read(autoTranscribeStoreProvider).load().then((enabled) {
      // A choice made while loading wins over the saved one.
      if (enabled != null && !_changed && ref.mounted) {
        state = enabled;
      }
    }, onError: (Object _) {});
    return false;
  }

  Future<void> set(bool enabled) async {
    _changed = true;
    state = enabled;
    try {
      await ref.read(autoTranscribeStoreProvider).save(enabled);
    } on Object {
      // Still applies for this session.
    }
  }
}
