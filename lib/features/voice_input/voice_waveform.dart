import 'package:flutter/material.dart';
import 'package:wecord/features/voice_input/voice_input_controller.dart';

/// The live waveform of voice input: a row of rounded bars, the newest on
/// the right, as tall as the loudness that was read. While nothing is heard
/// yet the bars rest as small dots.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    required this.levels,
    required this.color,
    this.restColor,
    this.height = 40,
    super.key,
  });

  final List<double> levels;
  final Color color;

  /// The color of bars that have not been filled yet.
  final Color? restColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Decorative: the words appear in the field, and the panel says it is
    // listening.
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavePainter(levels, color, restColor ?? color),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.color, this.restColor);

  final List<double> levels;
  final Color color;
  final Color restColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = voiceWaveBars;
    final slot = size.width / bars;
    final barWidth = (slot * 0.52).clamp(2.0, 6.0);
    final paint = Paint()..strokeCap = StrokeCap.round;
    final missing = bars - levels.length;
    for (var i = 0; i < bars; i++) {
      final filled = i >= missing;
      final level = filled ? levels[i - missing] : 0.0;
      // A soft curve so quiet speech still moves.
      final shaped = filled ? (level * 0.85 + 0.15) : 0.0;
      final barHeight = filled
          ? (size.height * shaped).clamp(barWidth, size.height)
          : barWidth;
      final x = slot * i + slot / 2;
      paint
        ..color = filled
            ? color.withValues(alpha: 0.45 + 0.55 * level)
            : restColor
        ..strokeWidth = barWidth;
      canvas.drawLine(
        Offset(x, (size.height - barHeight) / 2),
        Offset(x, (size.height + barHeight) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.levels != levels || old.color != color || old.restColor != restColor;
}
