import 'package:flutter/foundation.dart';
import 'package:wecord/features/care_mode/speech_reader.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// A voice that only remembers what it was asked to read. [finish] ends the
/// reading, like the device's voice reaching the end.
class FakeSpeechReader implements SpeechReader {
  FakeSpeechReader({this.supported = true, this.fails = false});

  final bool supported;

  /// The device refuses to speak.
  final bool fails;

  final spoken = <({String text, String language})>[];
  var stops = 0;
  final _speaking = ValueNotifier<bool>(false);

  @override
  bool get isSupported => supported;

  @override
  ValueListenable<bool> get speaking => _speaking;

  @override
  Future<void> speak(String text, {required String language}) async {
    if (fails) {
      throw const SpeechReaderException('no voice');
    }
    spoken.add((text: text, language: language));
    _speaking.value = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    _speaking.value = false;
  }

  /// The voice reached the end of the text.
  void finish() => _speaking.value = false;
}

/// The voice a test reads with. Care mode's own choices are set on the
/// world: `world.careStore.initial = ...`.
List<Override> careVoice(SpeechReader reader) => [
  speechReaderProvider.overrideWithValue(reader),
];
