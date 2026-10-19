import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/voice/captions/captions_controller.dart';
import 'package:wecord/features/voice/captions/captions_sheets.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How many settled lines the bar shows at once.
const captionBarLines = 3;

/// The most people named in "…'s device doesn't support captions".
const _maxNamedUnsupported = 2;

/// The caption bar of a call (E1): a notice that captions are on, what
/// people are saying, and what this device is doing about it. Shows nothing
/// while captions are off. Sits in the voice room under the header and in
/// the call card of a chat; it reads the dark voice room's colors.
///
/// Readable by design: the text is the room's ink on its panel, grows with
/// the system text size (the bar scrolls instead of clipping), the newest
/// settled line is a live region for screen readers (the line still being
/// spoken is left out, so it does not chatter), and nothing animates when
/// the system asks for reduced motion.
class CaptionStrip extends StatelessWidget {
  const CaptionStrip({super.key});

  @override
  Widget build(BuildContext context) {
    // On a wide window the bar stays a comfortable line length.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: const _CaptionStripBody(),
      ),
    );
  }
}

class _CaptionStripBody extends ConsumerWidget {
  const _CaptionStripBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final captions = ref.watch(captionsProvider);
    if (session == null || !session.isConnected || !captions.active) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final controller = ref.read(captionsProvider.notifier);
    final me = _localId(session);
    final hostName = captions.hostId == me
        ? null
        : captions.nameOf(captions.hostId ?? '');
    final title = hostName == null
        ? tr('Captions are on')
        : tr('Captions are on · {name}', {'name': hostName});

    if (captions.hidden) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Container(
          key: const ValueKey('caption-strip-hidden'),
          padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          child: Row(
            children: [
              Icon(Icons.closed_caption_rounded, size: 18, color: c.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Captions are on, but hidden here'),
                  style: TextStyle(fontSize: 13.5, color: c.ink),
                ),
              ),
              WeCordButton(
                key: const ValueKey('caption-strip-show'),
                label: tr('Show'),
                variant: WeCordButtonVariant.ghost,
                onPressed: () => controller.setHidden(false),
              ),
            ],
          ),
        ),
      );
    }

    final reduce = WeCordMotion.reduceMotion(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: AnimatedSize(
        duration: reduce ? Duration.zero : WeCordMotion.quick,
        alignment: Alignment.topCenter,
        child: Container(
          key: const ValueKey('caption-strip'),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
                child: Row(
                  children: [
                    Icon(Icons.closed_caption_rounded, size: 18, color: c.ink),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ),
                    WeCordIconButton(
                      key: const ValueKey('caption-strip-settings'),
                      tooltip: tr('Caption settings'),
                      icon: Icons.tune_rounded,
                      size: 36,
                      iconSize: 19,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: () =>
                          unawaited(showCaptionsSheet(context, ref)),
                    ),
                  ],
                ),
              ),
              _CaptionNotice(captions: captions),
              _CaptionLines(captions: captions, localId: me),
              _UnsupportedNotice(captions: captions),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}

String? _localId(VoiceSession session) {
  for (final participant in session.participants) {
    if (participant.isLocal) {
      return participant.userId;
    }
  }
  return null;
}

/// What this device is doing, when it is not simply listening: asks for
/// consent, says it can not, or that sharing is off.
class _CaptionNotice extends ConsumerWidget {
  const _CaptionNotice({required this.captions});

  final CaptionsState captions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final controller = ref.read(captionsProvider.notifier);
    final String? text;
    Widget? action;
    switch (captions.mic) {
      case CaptionMic.needsConsent:
        text = captions.engine == VoiceInputEngine.browser
            ? tr(
                "To make captions of you, your browser sends what you say to its speech service. Allow that to share your captions.",
              )
            : tr(
                "To make captions of you in this language, Apple's speech service listens to what you say. Allow that to share your captions.",
              );
        action = Row(
          children: [
            WeCordButton(
              key: const ValueKey('caption-allow-service'),
              label: tr('Allow'),
              variant: WeCordButtonVariant.secondary,
              onPressed: () => unawaited(controller.allowServer()),
            ),
            const SizedBox(width: 8),
            WeCordButton(
              key: const ValueKey('caption-decline-service'),
              label: tr('Not now'),
              variant: WeCordButtonVariant.ghost,
              onPressed: () => unawaited(controller.setSharing(false)),
            ),
          ],
        );
      case CaptionMic.unsupported:
        text = tr(
          "Your device can't make captions in this language. You still see everyone else's.",
        );
        action = WeCordButton(
          key: const ValueKey('caption-retry'),
          label: tr('Try again'),
          variant: WeCordButtonVariant.ghost,
          onPressed: controller.retry,
        );
      case CaptionMic.denied:
        text = tr(
          'Speech recognition or the microphone is turned off for WeCord, so your captions are not shared. Turn it on in Settings, then try again.',
        );
        action = WeCordButton(
          key: const ValueKey('caption-retry'),
          label: tr('Try again'),
          variant: WeCordButtonVariant.ghost,
          onPressed: controller.retry,
        );
      case CaptionMic.off when !captions.sharing:
        text = tr("You're not sharing your captions.");
      case CaptionMic.off:
      case CaptionMic.starting:
      case CaptionMic.listening:
      case CaptionMic.paused:
        text = null;
    }
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              key: const ValueKey('caption-notice'),
              style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
            ),
            if (action != null) ...[const SizedBox(height: 4), action],
          ],
        ),
      ),
    );
  }
}

/// The lines themselves: the last few settled ones, then whatever is being
/// said right now. Newest at the bottom.
class _CaptionLines extends StatelessWidget {
  const _CaptionLines({required this.captions, required this.localId});

  final CaptionsState captions;
  final String? localId;

  String _speaker(String userId) {
    if (userId == localId) {
      return tr('You');
    }
    return captions.nameOf(userId) ?? tr('Someone');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final settled = captions.lines.length <= captionBarLines
        ? captions.lines
        : captions.lines.sublist(captions.lines.length - captionBarLines);
    final live = captions.live.values.toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (settled.isEmpty && live.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        child: Text(
          tr('Waiting for someone to speak…'),
          key: const ValueKey('caption-empty'),
          style: TextStyle(fontSize: 14, color: c.muted),
        ),
      );
    }
    final lastSettled = settled.isEmpty ? null : settled.last;
    return ConstrainedBox(
      constraints: BoxConstraints(
        // Grows with the text size, never past half the screen.
        maxHeight: math.min(
          MediaQuery.sizeOf(context).height * 0.5,
          (MediaQuery.sizeOf(context).height * 0.34).clamp(120.0, 280.0) *
              math.max(1.0, MediaQuery.textScalerOf(context).scale(1)),
        ),
      ),
      child: ListView(
        key: const ValueKey('caption-lines'),
        reverse: true,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
        children: [
          // Reversed list: the newest first.
          for (final line in live.reversed)
            ExcludeSemantics(
              child: _CaptionRow(
                key: ValueKey('caption-live-${line.speakerId}'),
                speaker: _speaker(line.speakerId),
                text: line.text,
                self: line.speakerId == localId,
                live: true,
              ),
            ),
          for (final line in settled.reversed)
            Semantics(
              liveRegion: identical(line, lastSettled),
              container: true,
              child: _CaptionRow(
                key: ValueKey('caption-line-${line.speakerId}-${line.id}'),
                speaker: _speaker(line.speakerId),
                text: line.text,
                self: line.speakerId == localId,
              ),
            ),
        ],
      ),
    );
  }
}

class _CaptionRow extends StatelessWidget {
  const _CaptionRow({
    required this.speaker,
    required this.text,
    required this.self,
    this.live = false,
    super.key,
  });

  final String speaker;
  final String text;
  final bool self;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$speaker  ',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: self ? c.accent : c.muted,
              ),
            ),
            TextSpan(
              text: text,
              style: TextStyle(color: live ? c.muted : c.ink),
            ),
          ],
        ),
        style: const TextStyle(fontSize: 16, height: 1.35),
      ),
    );
  }
}

/// "Bart's device doesn't support captions."
class _UnsupportedNotice extends StatelessWidget {
  const _UnsupportedNotice({required this.captions});

  final CaptionsState captions;

  @override
  Widget build(BuildContext context) {
    final names = [
      for (final id in captions.unsupported)
        captions.nameOf(id) ?? tr('Someone'),
    ];
    if (names.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final shown = names.take(_maxNamedUnsupported).toList();
    final more = names.length - shown.length;
    final text = more > 0
        ? tr("{names} and {count} more: their devices don't support captions", {
            'names': shown.join(', '),
            'count': more,
          })
        : shown.length == 1
        ? tr("{name}'s device doesn't support captions", {'name': shown.first})
        : tr("{names}: their devices don't support captions", {
            'names': shown.join(', '),
          });
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Text(
        text,
        key: const ValueKey('caption-unsupported'),
        style: TextStyle(fontSize: 12.5, height: 1.3, color: c.muted),
      ),
    );
  }
}
