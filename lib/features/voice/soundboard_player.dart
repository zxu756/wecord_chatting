import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wecord/features/voice/soundboard_repository.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_sound.dart';

/// Plays soundboard clips on this device.
abstract interface class SoundboardPlayer {
  /// Plays the clip at [url] at [volume] (0 to 1), stopping after
  /// [maxCircleSoundDuration]. Clips may overlap.
  Future<void> play(String url, {required double volume});
}

final soundboardPlayerProvider = Provider<SoundboardPlayer>((ref) {
  return JustAudioSoundboardPlayer();
});

class JustAudioSoundboardPlayer implements SoundboardPlayer {
  @override
  Future<void> play(String url, {required double volume}) async {
    final player = AudioPlayer();
    try {
      await player.setUrl(url);
      try {
        await player.setClip(end: maxCircleSoundDuration);
      } catch (_) {
        // The timeout below stops it instead.
      }
      await player.setVolume(volume.clamp(0.0, 1.0));
      unawaited(player.play());
      await player.processingStateStream
          .firstWhere((state) => state == ProcessingState.completed)
          .timeout(maxCircleSoundDuration + const Duration(seconds: 1));
    } catch (_) {
      // A clip that won't load or play is skipped.
    } finally {
      await player.dispose();
    }
  }
}

/// Plays the sounds others play in the voice channel the current user is
/// connected to, at their soundboard volume, unless they are deafened.
class SoundboardPlayback {
  SoundboardPlayback({
    required this._repository,
    required this._player,
    required this._volume,
  });

  final SoundboardRepository _repository;
  final SoundboardPlayer _player;
  final double Function() _volume;

  String? _channelId;
  String? _circleId;
  var _hearing = false;
  StreamSubscription<SoundboardPlay>? _plays;

  /// The circle's sounds, loaded on the first play.
  final _sounds = <String, CircleSound>{};
  String? _soundsCircleId;

  /// Signed URLs by storage path, for the session.
  final _urls = <String, String>{};

  /// Follows [session]: listens to its channel's plays while connected to
  /// a circle voice channel.
  void follow(VoiceSession? session) {
    _hearing = session?.hearingWanted ?? false;
    final channelId =
        session != null && session.isConnected && session.circleId != null
        ? session.channelId
        : null;
    if (channelId == _channelId) {
      return;
    }
    unawaited(_plays?.cancel());
    _plays = null;
    _channelId = channelId;
    _circleId = channelId == null ? null : session!.circleId;
    if (channelId != null) {
      _plays = _repository
          .plays(channelId)
          .listen((play) => unawaited(_onPlay(play)), onError: (Object _) {});
    }
  }

  Future<void> _onPlay(SoundboardPlay play) async {
    final circleId = _circleId;
    if (!_hearing || circleId == null || play.channelId != _channelId) {
      return;
    }
    final volume = _volume();
    if (volume <= 0) {
      return;
    }
    try {
      final sound = await _soundFor(circleId, play.soundId);
      if (sound == null) {
        return;
      }
      final url = _urls[sound.storagePath] ??= await _repository.createSoundUrl(
        sound.storagePath,
      );
      if (!_hearing || play.channelId != _channelId) {
        return;
      }
      await _player.play(url, volume: volume);
    } catch (_) {
      // A sound that can't be loaded is skipped.
    }
  }

  Future<CircleSound?> _soundFor(String circleId, String soundId) async {
    if (_soundsCircleId != circleId || !_sounds.containsKey(soundId)) {
      final sounds = await _repository.listSounds(circleId);
      _sounds
        ..clear()
        ..addEntries(sounds.map((sound) => MapEntry(sound.id, sound)));
      _soundsCircleId = circleId;
    }
    return _sounds[soundId];
  }

  void dispose() {
    unawaited(_plays?.cancel());
    _plays = null;
    _channelId = null;
  }
}

/// A sound file chosen to upload.
class PickedSoundFile {
  const PickedSoundFile({required this.name, required this.bytes});

  /// The file's name, which suggests the sound's.
  final String name;
  final Uint8List bytes;
}

/// Asks for an MP3, Ogg or WAV file; null when cancelled. Throws
/// [SoundboardException] for files over [maxCircleSoundBytes].
typedef SoundFilePicker = Future<PickedSoundFile?> Function();

final soundFilePickerProvider = Provider<SoundFilePicker>((ref) {
  return () async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'audio',
          extensions: ['mp3', 'ogg', 'wav'],
          mimeTypes: ['audio/mpeg', 'audio/ogg', 'audio/wav', 'audio/x-wav'],
          uniformTypeIdentifiers: [
            'public.mp3',
            'org.xiph.ogg',
            'com.microsoft.waveform-audio',
          ],
        ),
      ],
    );
    if (file == null) {
      return null;
    }
    if (await file.length() > maxCircleSoundBytes) {
      throw SoundboardException(tr('Sounds can be at most 512 KB.'));
    }
    return PickedSoundFile(name: file.name, bytes: await file.readAsBytes());
  };
});
