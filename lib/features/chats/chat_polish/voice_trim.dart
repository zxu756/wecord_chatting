// Trimming a voice recording before it is sent (A10).
//
// The recorder writes 16-bit PCM WAV, so cutting is cutting samples: no
// encoder, no server, the same on every platform. The recording is paused,
// "Trim" opens [showVoiceTrimSheet] with the sound drawn as bars and two
// handles; what is chosen is a [VoiceTrimRange] that is applied to the
// recording when it is sent ([trimWav]).
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The shortest voice message that can be kept.
const minVoiceTrimMs = 500;

/// What to keep of a recording.
class VoiceTrimRange {
  const VoiceTrimRange({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  int get lengthMs => endMs - startMs;

  /// The whole recording of [durationMs] is kept.
  bool keepsAll(int durationMs) => startMs <= 0 && endMs >= durationMs;

  @override
  bool operator ==(Object other) =>
      other is VoiceTrimRange &&
      other.startMs == startMs &&
      other.endMs == endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);
}

/// Where the samples are in a PCM WAV file.
class WavLayout {
  const WavLayout({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset;
  final int dataLength;

  int get bytesPerFrame => channels * bitsPerSample ~/ 8;
  int get frames => dataLength ~/ bytesPerFrame;
  int get durationMs => frames * 1000 ~/ sampleRate;

  /// Reads the header of a PCM WAV; null for anything else.
  static WavLayout? parse(Uint8List wav) {
    if (wav.length < 44 ||
        String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(wav.sublist(8, 12)) != 'WAVE') {
      return null;
    }
    final data = ByteData.sublistView(wav);
    int? sampleRate;
    int? channels;
    int? bits;
    var offset = 12;
    while (offset + 8 <= wav.length) {
      final id = String.fromCharCodes(wav.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (id == 'fmt ' && body + 16 <= wav.length) {
        if (data.getUint16(body, Endian.little) != 1) {
          return null;
        }
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bits = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        if (sampleRate == null || channels == null || bits == null) {
          return null;
        }
        if (sampleRate <= 0 || channels <= 0 || bits < 8 || bits % 8 != 0) {
          return null;
        }
        final length = math.min(size, wav.length - body);
        return WavLayout(
          sampleRate: sampleRate,
          channels: channels,
          bitsPerSample: bits,
          dataOffset: body,
          dataLength: length,
        );
      }
      offset = body + size + (size.isOdd ? 1 : 0);
    }
    return null;
  }
}

/// [wav] cut to [startMs]..[endMs] as a new WAV; null when it is not a PCM
/// WAV or nothing is left.
Uint8List? trimWav(Uint8List wav, {required int startMs, required int endMs}) {
  final layout = WavLayout.parse(wav);
  if (layout == null) {
    return null;
  }
  final first = (math.max(0, startMs) * layout.sampleRate ~/ 1000).clamp(
    0,
    layout.frames,
  );
  final last = (math.max(0, endMs) * layout.sampleRate ~/ 1000).clamp(
    0,
    layout.frames,
  );
  if (last <= first) {
    return null;
  }
  final from = layout.dataOffset + first * layout.bytesPerFrame;
  final to = layout.dataOffset + last * layout.bytesPerFrame;
  final samples = wav.sublist(from, to);
  final out = Uint8List(44 + samples.length);
  final header = ByteData.sublistView(out);
  void ascii(int at, String text) {
    for (var index = 0; index < text.length; index++) {
      out[at + index] = text.codeUnitAt(index);
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + samples.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, layout.channels, Endian.little);
  header.setUint32(24, layout.sampleRate, Endian.little);
  header.setUint32(28, layout.sampleRate * layout.bytesPerFrame, Endian.little);
  header.setUint16(32, layout.bytesPerFrame, Endian.little);
  header.setUint16(34, layout.bitsPerSample, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, samples.length, Endian.little);
  out.setRange(44, out.length, samples);
  return out;
}

/// The loudness of [wav] in [count] slices, each 0 to 1 (16-bit WAVs; other
/// sizes read as flat).
List<double> wavPeaks(Uint8List wav, int count) {
  final layout = WavLayout.parse(wav);
  if (layout == null || count <= 0 || layout.bitsPerSample != 16) {
    return List<double>.filled(math.max(count, 0), 0);
  }
  final frames = layout.frames;
  if (frames == 0) {
    return List<double>.filled(count, 0);
  }
  final data = ByteData.sublistView(wav);
  final peaks = List<double>.filled(count, 0);
  final perSlice = math.max(1, frames ~/ count);
  // A slice looks at up to 200 evenly spread frames.
  final step = math.max(1, perSlice ~/ 200);
  for (var slice = 0; slice < count; slice++) {
    final startFrame = (frames * slice) ~/ count;
    final endFrame = math.min(frames, (frames * (slice + 1)) ~/ count);
    var peak = 0;
    for (var frame = startFrame; frame < endFrame; frame += step) {
      final at = layout.dataOffset + frame * layout.bytesPerFrame;
      if (at + 2 > wav.length) {
        break;
      }
      final value = data.getInt16(at, Endian.little).abs();
      if (value > peak) {
        peak = value;
      }
    }
    peaks[slice] = (peak / 32768).clamp(0.0, 1.0);
  }
  return peaks;
}

/// "0:07" or "0:07.5" style time for a handle.
String voiceTrimTime(int ms) {
  final seconds = ms ~/ 1000;
  final tenth = (ms % 1000) ~/ 100;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}.$tenth';
}

/// Plays a cut of the recording so the person can hear what stays.
abstract interface class VoiceTrimPreview {
  Future<void> play(Uint8List wav);
  Future<void> stop();
  Stream<bool> get playing;
  Future<void> dispose();
}

class _JustAudioTrimPreview implements VoiceTrimPreview {
  final _player = AudioPlayer();

  @override
  Stream<bool> get playing => _player.playerStateStream.map(
    (state) =>
        state.playing && state.processingState != ProcessingState.completed,
  );

  @override
  Future<void> play(Uint8List wav) async {
    await _player.setAudioSource(_WavSource(wav));
    await _player.seek(Duration.zero);
    unawaited(_player.play());
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

class _WavSource extends StreamAudioSource {
  _WavSource(this._bytes);

  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(_bytes.sublist(from, to)),
      contentType: 'audio/wav',
    );
  }
}

/// Opens the trim sheet for [wav] (what was recorded so far). Returns the
/// range chosen, or null when it was dismissed without choosing.
Future<VoiceTrimRange?> showVoiceTrimSheet(
  BuildContext context, {
  required Uint8List wav,
  VoiceTrimRange? initial,
  VoiceTrimPreview Function()? previewBuilder,
}) {
  return showWeCordSheet<VoiceTrimRange>(
    context,
    title: tr('Trim voice message'),
    builder: (context, _) => VoiceTrimView(
      wav: wav,
      initial: initial,
      previewBuilder: previewBuilder,
    ),
  );
}

/// The content of the trim sheet.
class VoiceTrimView extends StatefulWidget {
  const VoiceTrimView({
    required this.wav,
    this.initial,
    this.previewBuilder,
    super.key,
  });

  final Uint8List wav;
  final VoiceTrimRange? initial;
  final VoiceTrimPreview Function()? previewBuilder;

  @override
  State<VoiceTrimView> createState() => _VoiceTrimViewState();
}

class _VoiceTrimViewState extends State<VoiceTrimView> {
  static const _bars = 48;

  late final int _durationMs;
  late final List<double> _peaks;
  late int _start;
  late int _end;
  VoiceTrimPreview? _preview;
  StreamSubscription<bool>? _previewSubscription;
  var _previewing = false;

  @override
  void initState() {
    super.initState();
    _durationMs = WavLayout.parse(widget.wav)?.durationMs ?? 0;
    _peaks = wavPeaks(widget.wav, _bars);
    _start = (widget.initial?.startMs ?? 0).clamp(0, _durationMs);
    _end = (widget.initial?.endMs ?? _durationMs).clamp(_start, _durationMs);
  }

  @override
  void dispose() {
    unawaited(_previewSubscription?.cancel());
    final preview = _preview;
    if (preview != null) {
      unawaited(preview.stop().whenComplete(preview.dispose));
    }
    super.dispose();
  }

  void _changed(RangeValues values) {
    var start = values.start.round();
    var end = values.end.round();
    // The handles keep a little sound between them.
    if (end - start < minVoiceTrimMs) {
      if (start != _start) {
        start = math.max(0, end - minVoiceTrimMs);
      } else {
        end = math.min(_durationMs, start + minVoiceTrimMs);
      }
    }
    setState(() {
      _start = start;
      _end = end;
    });
    if (_previewing) {
      unawaited(_stopPreview());
    }
  }

  Future<void> _stopPreview() async {
    await _preview?.stop();
    if (mounted) {
      setState(() => _previewing = false);
    }
  }

  Future<void> _togglePreview() async {
    if (_previewing) {
      await _stopPreview();
      return;
    }
    final cut = trimWav(widget.wav, startMs: _start, endMs: _end);
    if (cut == null) {
      return;
    }
    var preview = _preview;
    if (preview == null) {
      preview = (widget.previewBuilder ?? _JustAudioTrimPreview.new)();
      _preview = preview;
      _previewSubscription = preview.playing.listen((playing) {
        if (mounted && _previewing != playing) {
          setState(() => _previewing = playing);
        }
      });
    }
    setState(() => _previewing = true);
    try {
      await preview.play(cut);
    } catch (_) {
      if (mounted) {
        setState(() => _previewing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final length = _end - _start;
    final disabled = _durationMs < minVoiceTrimMs;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Drag the handles to keep only the part you want.'),
              style: TextStyle(fontSize: 13.5, color: c.muted),
            ),
            const SizedBox(height: 14),
            ExcludeSemantics(
              child: SizedBox(
                key: const ValueKey('voice-trim-wave'),
                height: 56,
                child: CustomPaint(
                  painter: _TrimWavePainter(
                    peaks: _peaks,
                    from: _durationMs == 0 ? 0 : _start / _durationMs,
                    to: _durationMs == 0 ? 1 : _end / _durationMs,
                    kept: c.accent,
                    dropped: c.line,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            RangeSlider(
              key: const ValueKey('voice-trim-slider'),
              values: RangeValues(_start.toDouble(), _end.toDouble()),
              min: 0,
              max: math.max(_durationMs, 1).toDouble(),
              onChanged: disabled ? null : _changed,
              semanticFormatterCallback: (value) =>
                  voiceTrimTime(value.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  voiceTrimTime(_start),
                  key: const ValueKey('voice-trim-start'),
                  style: _timeStyle(c.muted),
                ),
                Text(
                  tr('Keeps {time}', {'time': voiceTrimTime(length)}),
                  key: const ValueKey('voice-trim-length'),
                  style: _timeStyle(c.ink),
                ),
                Text(
                  voiceTrimTime(_end),
                  key: const ValueKey('voice-trim-end'),
                  style: _timeStyle(c.muted),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                WeCordIconButton(
                  key: const ValueKey('voice-trim-preview'),
                  tooltip: _previewing ? tr('Stop') : tr('Listen'),
                  icon: _previewing
                      ? Icons.stop_rounded
                      : Icons.play_arrow_rounded,
                  variant: WeCordButtonVariant.secondary,
                  onPressed: disabled
                      ? null
                      : () => unawaited(_togglePreview()),
                ),
                const SizedBox(width: 8),
                WeCordButton(
                  key: const ValueKey('voice-trim-reset'),
                  label: tr('Keep all'),
                  variant: WeCordButtonVariant.secondary,
                  onPressed: _start == 0 && _end == _durationMs
                      ? null
                      : () => _changed(RangeValues(0, _durationMs.toDouble())),
                ),
                const Spacer(),
                WeCordButton(
                  key: const ValueKey('voice-trim-done'),
                  label: tr('Done'),
                  onPressed: disabled
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(VoiceTrimRange(startMs: _start, endMs: _end)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _timeStyle(Color color) => TextStyle(
    fontSize: 12.5,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

class _TrimWavePainter extends CustomPainter {
  const _TrimWavePainter({
    required this.peaks,
    required this.from,
    required this.to,
    required this.kept,
    required this.dropped,
  });

  final List<double> peaks;
  final double from;
  final double to;
  final Color kept;
  final Color dropped;

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) {
      return;
    }
    final slot = size.width / peaks.length;
    final barWidth = math.max(1.5, slot * 0.6);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var index = 0; index < peaks.length; index++) {
      final middle = (index + 0.5) / peaks.length;
      paint.color = middle >= from && middle <= to ? kept : dropped;
      paint.strokeWidth = barWidth;
      final height = math.max(4.0, peaks[index] * size.height);
      final x = slot * (index + 0.5);
      canvas.drawLine(
        Offset(x, (size.height - height) / 2),
        Offset(x, (size.height + height) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TrimWavePainter old) =>
      old.from != from ||
      old.to != to ||
      old.kept != kept ||
      old.dropped != dropped ||
      !identical(old.peaks, peaks);
}
