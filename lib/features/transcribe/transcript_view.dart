import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/transcribe/transcribe_controller.dart';
import 'package:wecord/features/transcribe/transcribe_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The small "Transcribe" button next to a voice message's player: shows the
/// text under the waveform, or hides it again.
class TranscribeButton extends ConsumerWidget {
  const TranscribeButton({
    required this.request,
    required this.color,
    super.key,
  });

  final TranscribeRequest request;

  /// The bubble's text color, which the icon follows.
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(
      transcriptsProvider.select((all) => all.containsKey(request.messageId)),
    );
    final controller = ref.read(transcriptsProvider.notifier);
    final label = shown ? tr('Hide transcript') : tr('Transcribe');
    return WeCordPressable(
      key: const ValueKey('voice-transcribe-button'),
      onPressed: () => shown
          ? controller.hide(request.messageId)
          : unawaited(controller.show(request)),
      tooltip: label,
      semanticLabel: label,
      shape: const CircleBorder(),
      pressedScale: 0.9,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: shown
                ? color.withValues(alpha: 0.18)
                : hovered
                ? color.withValues(alpha: 0.1)
                : null,
          ),
          child: Icon(
            shown ? Icons.subtitles_rounded : Icons.subtitles_outlined,
            size: 18,
            color: color.withValues(alpha: shown ? 1 : 0.75),
          ),
        );
      },
    );
  }
}

/// The transcript under a voice message's waveform: a spinner while it is
/// made, the text with a way to hide it, or what went wrong with a retry.
/// Nothing when the message isn't being transcribed. When Settings → AI →
/// Auto-transcribe is on it starts the transcription itself, on the device.
class TranscriptView extends ConsumerStatefulWidget {
  const TranscriptView({required this.request, required this.color, super.key});

  final TranscribeRequest request;
  final Color color;

  @override
  ConsumerState<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends ConsumerState<TranscriptView> {
  @override
  void initState() {
    super.initState();
    if (ref.read(autoTranscribeProvider)) {
      _auto();
    }
  }

  void _auto() {
    // After the first frame, so a long list does not start work while it is
    // still being built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(autoTranscribeProvider)) {
        ref.read(transcriptsProvider.notifier).autoTranscribe(widget.request);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(autoTranscribeProvider, (previous, next) {
      if (next) {
        _auto();
      }
    });
    final request = widget.request;
    final transcript = ref.watch(
      transcriptsProvider.select((all) => all[request.messageId]),
    );
    if (transcript == null) {
      return const SizedBox.shrink();
    }
    final color = widget.color;
    final caption = color.withValues(alpha: 0.7);
    final controller = ref.read(transcriptsProvider.notifier);

    Widget link(String label, VoidCallback onPressed, {Key? key}) {
      return WeCordPressable(
        key: key,
        onPressed: onPressed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        builder: (context, states) => Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      );
    }

    Widget note(String text, {Key? key}) {
      return Semantics(
        liveRegion: true,
        child: Text(
          text,
          key: key,
          style: TextStyle(fontSize: 13, height: 1.4, color: color),
        ),
      );
    }

    final Widget body;
    switch (transcript.phase) {
      case TranscriptPhase.loading:
        body = Semantics(
          liveRegion: true,
          label: tr('Transcribing…'),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: caption,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  tr('Transcribing…'),
                  style: TextStyle(fontSize: 13, color: caption),
                ),
              ],
            ),
          ),
        );
      case TranscriptPhase.needsConsent:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            note(
              tr(
                "This device can't transcribe this language by itself. To go on, the audio is sent to Apple's speech service.",
              ),
              key: const ValueKey('voice-transcript-consent'),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                link(
                  tr('Send to Apple'),
                  () => unawaited(controller.confirmServerRecognition(request)),
                  key: const ValueKey('voice-transcript-send-to-apple'),
                ),
                link(
                  tr('Cancel'),
                  () => controller.hide(request.messageId),
                  key: const ValueKey('voice-transcript-cancel'),
                ),
              ],
            ),
          ],
        );
      case TranscriptPhase.done:
        final engine = transcript.engine;
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              liveRegion: true,
              label: tr('Transcript: {text}', {'text': transcript.text ?? ''}),
              child: ExcludeSemantics(
                child: Text(
                  transcript.text ?? '',
                  key: const ValueKey('voice-transcript-text'),
                  style: TextStyle(fontSize: 14.5, height: 1.45, color: color),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (engine != null)
                  Text(
                    transcribeEngineCaption(engine),
                    style: TextStyle(fontSize: 12, color: caption),
                  ),
                link(
                  tr('Hide transcript'),
                  () => controller.hide(request.messageId),
                  key: const ValueKey('voice-transcript-hide'),
                ),
              ],
            ),
          ],
        );
      case TranscriptPhase.failed:
        final error =
            transcript.error ??
            const TranscribeException(TranscribeFailureKind.failed);
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            note(
              transcribeErrorMessage(error),
              key: const ValueKey('voice-transcript-error'),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              children: [
                if (transcribeCanRetry(error))
                  link(
                    tr('Try again'),
                    () => unawaited(controller.show(request)),
                    key: const ValueKey('voice-transcript-retry'),
                  ),
                link(
                  tr('Dismiss'),
                  () => controller.hide(request.messageId),
                  key: const ValueKey('voice-transcript-dismiss'),
                ),
              ],
            ),
          ],
        );
      case TranscriptPhase.unavailable:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            note(
              transcribeUnavailableMessage(
                transcript.unavailable ?? TranscribeUnavailable.platform,
              ),
              key: const ValueKey('voice-transcript-unavailable'),
            ),
            const SizedBox(height: 4),
            link(
              tr('Dismiss'),
              () => controller.hide(request.messageId),
              key: const ValueKey('voice-transcript-dismiss'),
            ),
          ],
        );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        key: const ValueKey('voice-transcript'),
        padding: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: color.withValues(alpha: 0.18))),
        ),
        child: body,
      ),
    );
  }
}
