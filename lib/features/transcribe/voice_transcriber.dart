import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';

/// Turns a voice message into text. The iPhone and Mac apps do it with the
/// system's speech recognizer, on the device; the web asks the server's
/// speech-to-text provider when there is one. Tests swap in a fake.
abstract interface class VoiceTranscriber {
  /// Whether this transcriber reads the audio on the device itself, so it
  /// may run on its own (Settings → AI → Auto-transcribe).
  bool get runsOnDevice;

  /// What can be done for [request]. Never asks for any permission.
  Future<TranscribePlan> plan(TranscribeRequest request);

  /// The transcript of [request]'s audio. With [allowServerRecognition] a
  /// language the device can't recognize on its own may go to Apple's
  /// servers; without it that throws [TranscribeFailureKind.needsServer].
  /// Speech recognition permission is asked for here, the first time.
  Future<VoiceTranscript> transcribe(
    TranscribeRequest request, {
    bool allowServerRecognition = false,
  });
}

/// Where transcription isn't possible (Android, Windows, Linux, and tests
/// that don't set one up).
class UnsupportedVoiceTranscriber implements VoiceTranscriber {
  const UnsupportedVoiceTranscriber();

  @override
  bool get runsOnDevice => false;

  @override
  Future<TranscribePlan> plan(TranscribeRequest request) async =>
      const TranscribePlan.unavailable(TranscribeUnavailable.platform);

  @override
  Future<VoiceTranscript> transcribe(
    TranscribeRequest request, {
    bool allowServerRecognition = false,
  }) => Future.error(const TranscribeException(TranscribeFailureKind.failed));
}

/// The system's speech recognizer through the Runner apps' `TranscribePlugin`
/// (channel `wecord/transcribe`): `SFSpeechRecognizer` on the downloaded
/// audio file, on the device when the language supports it.
class NativeVoiceTranscriber implements VoiceTranscriber {
  NativeVoiceTranscriber({
    required this.fetchAudio,
    this._channel = const MethodChannel('wecord/transcribe'),
  });

  /// The local path of the request's audio, downloading it if needed.
  final Future<String> Function(TranscribeRequest request) fetchAudio;
  final MethodChannel _channel;

  @override
  bool get runsOnDevice => true;

  @override
  Future<TranscribePlan> plan(TranscribeRequest request) async {
    final Map<String, Object?>? info;
    try {
      info = await _channel.invokeMapMethod<String, Object?>('capabilities', {
        'locales': request.locales,
      });
    } on MissingPluginException {
      return const TranscribePlan.unavailable(TranscribeUnavailable.platform);
    }
    if (info == null || info['supported'] != true) {
      return const TranscribePlan.unavailable(TranscribeUnavailable.language);
    }
    if (info['onDevice'] == true) {
      final denied =
          info['authorization'] == 'denied' ||
          info['authorization'] == 'restricted';
      return TranscribePlan.engine(
        TranscribeEngine.onDevice,
        canAutoStart: !denied,
      );
    }
    return const TranscribePlan.engine(TranscribeEngine.appleServer);
  }

  @override
  Future<VoiceTranscript> transcribe(
    TranscribeRequest request, {
    bool allowServerRecognition = false,
  }) async {
    final path = await fetchAudio(request);
    try {
      final result = await _channel
          .invokeMapMethod<String, Object?>('transcribe', {
            'path': path,
            'locales': request.locales,
            'allowServer': allowServerRecognition,
          });
      final text = (result?['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) {
        throw const TranscribeException(TranscribeFailureKind.noSpeech);
      }
      return VoiceTranscript(
        text,
        result?['onDevice'] == true
            ? TranscribeEngine.onDevice
            : TranscribeEngine.appleServer,
      );
    } on PlatformException catch (error) {
      throw TranscribeException(switch (error.code) {
        'not_authorized' => TranscribeFailureKind.notAuthorized,
        'no_speech' => TranscribeFailureKind.noSpeech,
        'unreadable' => TranscribeFailureKind.unreadable,
        'unavailable' => TranscribeFailureKind.unavailable,
        'needs_server' => TranscribeFailureKind.needsServer,
        _ => TranscribeFailureKind.failed,
      });
    }
  }
}

/// The server's speech-to-text provider through the `ai` function (the
/// web). The server finds the audio from the message id itself.
class ServerVoiceTranscriber implements VoiceTranscriber {
  const ServerVoiceTranscriber(this._ai);

  final AiRepository _ai;

  @override
  bool get runsOnDevice => false;

  @override
  Future<TranscribePlan> plan(TranscribeRequest request) async {
    try {
      final status = await _ai.status();
      return status.transcribeConfigured
          ? const TranscribePlan.engine(TranscribeEngine.aiServer)
          : const TranscribePlan.unavailable(TranscribeUnavailable.platform);
    } on AiNotConfiguredException {
      return const TranscribePlan.unavailable(TranscribeUnavailable.platform);
    }
  }

  @override
  Future<VoiceTranscript> transcribe(
    TranscribeRequest request, {
    bool allowServerRecognition = false,
  }) async {
    try {
      final text = await _ai.transcribe(messageId: request.messageId);
      if (text.isEmpty) {
        throw const TranscribeException(TranscribeFailureKind.noSpeech);
      }
      return VoiceTranscript(text, TranscribeEngine.aiServer);
    } on AiTranscribeNotConfiguredException {
      throw const TranscribeException(TranscribeFailureKind.unavailable);
    }
  }
}

bool get _isApple =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// The file name an audio attachment is kept under, with an extension the
/// system recognizes the format by.
String voiceFileName(TranscribeRequest request) {
  final mime = request.attachment.mimeType.split(';').first.trim();
  final extension = switch (mime) {
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
    'audio/mp4' || 'audio/m4a' || 'audio/x-m4a' || 'audio/aac' => 'm4a',
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    'audio/ogg' => 'ogg',
    'audio/webm' => 'webm',
    _ =>
      request.attachment.path.contains('.')
          ? request.attachment.path.split('.').last
          : 'wav',
  };
  return 'voice-${request.messageId}.$extension';
}

/// Downloads the audio of a voice message to a local file (kept in the file
/// viewer's download cache).
final voiceAudioFetcherProvider =
    Provider<Future<String> Function(TranscribeRequest)>((ref) {
      return (request) {
        final attachment = request.attachment;
        final file = PreviewFile(
          bucket: attachment.bucket,
          path: attachment.path,
          name: voiceFileName(request),
          mimeType: attachment.mimeType,
          size: attachment.size,
          messageId: request.messageId,
          conversationId: request.conversationId,
        );
        return ref
            .read(fileFetcherProvider)
            .download(
              file,
              url: () async => Uri.parse(
                await ref
                    .read(chatsRepositoryProvider)
                    .createVoiceUrl(attachment),
              ),
            );
      };
    });

/// How voice messages are transcribed on this platform: the system's
/// recognizer on iOS and macOS, the server on the web, nothing elsewhere.
final voiceTranscriberProvider = Provider<VoiceTranscriber>((ref) {
  if (kIsWeb) {
    return ServerVoiceTranscriber(ref.watch(aiRepositoryProvider));
  }
  if (_isApple) {
    return NativeVoiceTranscriber(
      fetchAudio: ref.watch(voiceAudioFetcherProvider),
    );
  }
  return const UnsupportedVoiceTranscriber();
});
