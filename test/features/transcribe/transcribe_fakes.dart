import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/transcribe/transcribe_controller.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/features/transcribe/transcript_cache.dart';
import 'package:wecord/features/transcribe/voice_transcriber.dart';
import 'package:wecord/shared/models/message.dart';

const testVoice = VoiceAttachment(
  bucket: 'voice-messages',
  path: 'conversation-1/voice-1.wav',
  mimeType: 'audio/wav',
  size: 3,
  durationMs: 4200,
);

VoiceAttachment voiceWith(String mimeType, String path) => VoiceAttachment(
  bucket: 'voice-messages',
  path: path,
  mimeType: mimeType,
  size: 3,
  durationMs: 1000,
);

TranscribeRequest testRequest([String id = 'message-1']) => TranscribeRequest(
  messageId: id,
  conversationId: 'conversation-1',
  attachment: testVoice,
  locales: const ['en-US'],
);

/// A [VoiceTranscriber] for tests: what it plans and answers is set up
/// front, calls are recorded.
class FakeVoiceTranscriber implements VoiceTranscriber {
  FakeVoiceTranscriber({
    this.planValue = const TranscribePlan.engine(
      TranscribeEngine.onDevice,
      canAutoStart: true,
    ),
    this.runsOnDevice = true,
  });

  TranscribePlan planValue;

  @override
  bool runsOnDevice;

  /// What [transcribe] gives back.
  String text = 'Lunch at noon?';
  TranscribeEngine engine = TranscribeEngine.onDevice;

  /// Thrown by [transcribe] when set (once, when [errorOnce]).
  Object? error;
  bool errorOnce = true;

  /// Holds [transcribe] until completed (for the loading state).
  Completer<void>? gate;

  final planCalls = <String>[];
  final transcribeCalls = <({String messageId, bool allowServer})>[];

  @override
  Future<TranscribePlan> plan(TranscribeRequest request) async {
    planCalls.add(request.messageId);
    return planValue;
  }

  @override
  Future<VoiceTranscript> transcribe(
    TranscribeRequest request, {
    bool allowServerRecognition = false,
  }) async {
    transcribeCalls.add((
      messageId: request.messageId,
      allowServer: allowServerRecognition,
    ));
    await gate?.future;
    if (error case final failure?) {
      if (errorOnce) {
        error = null;
      }
      throw failure;
    }
    return VoiceTranscript(text, engine);
  }
}

/// The overrides a test needs to use [transcriber] with no device, server or
/// disk.
List<Override> transcribeOverrides(
  FakeVoiceTranscriber transcriber, {
  InMemoryTranscriptCache? cache,
  AutoTranscribeStore? autoStore,
  AiRepository? ai,
}) => [
  voiceTranscriberProvider.overrideWithValue(transcriber),
  transcriptCacheProvider.overrideWithValue(cache ?? InMemoryTranscriptCache()),
  autoTranscribeStoreProvider.overrideWithValue(
    autoStore ?? InMemoryAutoTranscribeStore(),
  ),
  if (ai != null) aiRepositoryProvider.overrideWithValue(ai),
];
