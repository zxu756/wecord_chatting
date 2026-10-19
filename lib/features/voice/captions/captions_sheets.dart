import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/voice/captions/captions_controller.dart';
import 'package:wecord/features/voice/captions/recap/meeting_recap_sheet.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/features/voice/voice_ui.dart';
import 'package:wecord/features/voice_input/voice_input_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Fewer lines than this are not worth a recap.
const minRecapLines = 3;

// -------------------------------------------------------------- the button --

/// The captions button of a call: turns captions on for people who may
/// (the voice server says so), opens the caption settings while they are on.
/// Nothing for everyone else while captions are off.
class CaptionsButton extends ConsumerWidget {
  const CaptionsButton({this.size, super.key});

  /// The button's size; the header size by default.
  final double? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(voiceSessionProvider);
    final active = ref.watch(captionsProvider.select((s) => s.active));
    final canHost = ref.watch(captionsCanHostProvider);
    if (session == null || !session.isConnected || (!active && !canHost)) {
      return const SizedBox.shrink();
    }
    return VoiceControlButton(
      key: const ValueKey('voice-captions-button'),
      icon: active
          ? Icons.closed_caption_rounded
          : Icons.closed_caption_outlined,
      tooltip: active ? tr('Caption settings') : tr('Turn on captions'),
      on: active,
      size: size ?? (usesTouchInput(context) ? 42 : 38),
      onPressed: () => unawaited(
        active
            ? showCaptionsSheet(context, ref)
            : showCaptionsStartSheet(context, ref),
      ),
    );
  }
}

// ----------------------------------------------------------- turning on --

/// Explains captions and turns them on.
Future<void> showCaptionsStartSheet(BuildContext context, WidgetRef ref) {
  final container = ProviderScope.containerOf(context);
  return showWeCordSheet<void>(
    context,
    title: tr('Turn on captions?'),
    builder: (sheetContext, _) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        20 + MediaQuery.paddingOf(sheetContext).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Point(
            icon: Icons.visibility_outlined,
            text: tr('Everyone in the call sees that captions are on.'),
          ),
          _Point(
            icon: Icons.phone_iphone_rounded,
            text: tr(
              "Each person's device turns what they say into text. Only the text is shared with the call.",
            ),
          ),
          _Point(
            icon: Icons.person_off_outlined,
            text: tr('Anyone can choose not to share their captions.'),
          ),
          _Point(
            icon: Icons.mic_off_outlined,
            text: tr(
              'Nothing is recorded and no audio is saved. The words stay in memory on the devices until the call ends, unless you write a recap.',
            ),
          ),
          const SizedBox(height: 14),
          WeCordButton(
            key: const ValueKey('captions-start'),
            label: tr('Turn on captions'),
            icon: Icons.closed_caption_rounded,
            expand: true,
            size: WeCordButtonSize.large,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              unawaited(container.read(captionsProvider.notifier).start());
            },
          ),
        ],
      ),
    ),
  );
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- settings --

/// This person's caption settings: sharing their own captions, the
/// language, the transcript so far, hiding the bar, and (for whoever may)
/// turning captions off.
Future<void> showCaptionsSheet(BuildContext context, WidgetRef ref) {
  return showWeCordSheet<void>(
    context,
    title: tr('Captions'),
    builder: (sheetContext, _) => const CaptionsSettings(),
  );
}

class CaptionsSettings extends ConsumerWidget {
  const CaptionsSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captions = ref.watch(captionsProvider);
    final canHost = ref.watch(captionsCanHostProvider);
    final controller = ref.read(captionsProvider.notifier);
    final c = context.tokens.colors;
    final unsupported = captions.mic == CaptionMic.unsupported;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!captions.active)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                tr('Captions are off.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: c.muted),
              ),
            )
          else ...[
            SettingsGroup(
              separatorIndent: 58,
              footer: unsupported
                  ? tr("Your device can't make captions in this language.")
                  : tr(
                      'Your device turns what you say into text and shares the text with the call. Your voice is not recorded.',
                    ),
              children: [
                SettingsRow.toggle(
                  key: const ValueKey('captions-share'),
                  icon: Icons.record_voice_over_outlined,
                  title: tr('Share my captions'),
                  value: captions.sharing,
                  onChanged: (value) => unawaited(controller.setSharing(value)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            WeCordSegmented<VoiceInputLanguage>(
              segments: [
                for (final language in VoiceInputLanguage.values)
                  WeCordSegment(value: language, label: language.label),
              ],
              selected: captions.language,
              expand: true,
              semanticLabel: tr('Language I speak'),
              onChanged: (language) =>
                  unawaited(controller.setLanguage(language)),
            ),
            const SizedBox(height: 14),
            SettingsGroup(
              separatorIndent: 58,
              children: [
                SettingsRow(
                  key: const ValueKey('captions-transcript'),
                  icon: Icons.notes_rounded,
                  title: tr('Transcript'),
                  value: '${captions.lines.length}',
                  onTap: () => unawaited(showCaptionTranscript(context)),
                ),
                SettingsRow(
                  key: const ValueKey('captions-hide'),
                  icon: captions.hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  title: captions.hidden
                      ? tr('Show captions on my screen')
                      : tr('Hide captions on my screen'),
                  onTap: () {
                    controller.setHidden(!captions.hidden);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            if (canHost) ...[
              const SizedBox(height: 18),
              WeCordButton(
                key: const ValueKey('captions-stop'),
                label: tr('Turn off captions'),
                icon: Icons.closed_caption_disabled_outlined,
                variant: WeCordButtonVariant.secondary,
                expand: true,
                size: WeCordButtonSize.large,
                onPressed: () {
                  final navigator = Navigator.of(context);
                  unawaited(() async {
                    navigator.pop();
                    await stopCaptionsOfferingRecap(navigator.context);
                  }());
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- transcript --

/// The words so far, who said them and when.
Future<void> showCaptionTranscript(BuildContext context) {
  return showWeCordSheet<void>(
    context,
    title: tr('Transcript'),
    detents: const [0.5, 0.92],
    initialDetent: 0.7,
    builder: (sheetContext, scrollController) =>
        CaptionTranscriptView(scrollController: scrollController),
  );
}

class CaptionTranscriptView extends ConsumerWidget {
  const CaptionTranscriptView({this.scrollController, super.key});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final captions = ref.watch(captionsProvider);
    final c = context.tokens.colors;
    if (captions.lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          tr('Nothing has been said yet.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14.5, color: c.muted),
        ),
      );
    }
    final localizations = MaterialLocalizations.of(context);
    return ListView.builder(
      controller: scrollController,
      shrinkWrap: scrollController == null,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: captions.lines.length + 1,
      itemBuilder: (context, index) {
        if (index == captions.lines.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              tr(
                'This transcript is only on your device, in memory. It is gone when the call ends.',
              ),
              style: TextStyle(fontSize: 12.5, height: 1.4, color: c.subtle),
            ),
          );
        }
        final line = captions.lines[index];
        final time = localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(line.at),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${captions.nameOf(line.speakerId) ?? tr('Someone')}  ',
                  style: TextStyle(fontWeight: FontWeight.w800, color: c.muted),
                ),
                TextSpan(
                  text: '$time  ',
                  style: TextStyle(fontSize: 12, color: c.subtle),
                ),
                TextSpan(
                  text: line.text,
                  style: TextStyle(color: c.ink),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
        );
      },
    );
  }
}

// ----------------------------------------------------- turning off / recap --

enum _StopChoice { recap, stop }

/// Asks how to end captions: with a recap (when AI is on and there is
/// something to write about) or without. Does nothing when cancelled.
Future<void> stopCaptionsOfferingRecap(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final captions = container.read(captionsProvider);
  final session = container.read(voiceSessionProvider);
  if (!captions.active) {
    return;
  }
  final recapPossible =
      container.read(aiAvailableProvider(session?.circleId)) &&
      captions.lines.length >= minRecapLines;
  var choice = _StopChoice.stop;
  if (recapPossible) {
    final picked = await _askStop(navigator.context, leaving: false);
    if (picked == null) {
      return;
    }
    choice = picked;
  }
  final transcript = await container.read(captionsProvider.notifier).stop();
  if (choice == _StopChoice.recap && transcript != null && navigator.mounted) {
    await showMeetingRecapSheet(
      navigator.context,
      transcript: transcript,
      useRootNavigator: true,
    );
  }
}

/// Leaves the call. If captions are on and this person may turn them off,
/// they are offered a recap of what was said first (the words are gone once
/// the call ends).
Future<void> leaveCallOfferingRecap(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final session = container.read(voiceSessionProvider);
  final captions = container.read(captionsProvider);
  final canHost = container.read(captionsCanHostProvider);
  final controller = container.read(voiceSessionProvider.notifier);
  if (session == null || !captions.active || !canHost) {
    await controller.leave();
    return;
  }
  final recapPossible =
      container.read(aiAvailableProvider(session.circleId)) &&
      captions.lines.length >= minRecapLines;
  if (!recapPossible) {
    await controller.leave();
    return;
  }
  final picked = await _askStop(navigator.context, leaving: true);
  if (picked == null) {
    return;
  }
  CaptionTranscript? transcript;
  if (picked == _StopChoice.recap) {
    transcript = await container.read(captionsProvider.notifier).stop();
  }
  await controller.leave();
  if (transcript != null && navigator.mounted) {
    await showMeetingRecapSheet(
      navigator.context,
      transcript: transcript,
      useRootNavigator: true,
    );
  }
}

Future<_StopChoice?> _askStop(BuildContext context, {required bool leaving}) {
  return showDialog<_StopChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('captions-stop-dialog'),
      scrollable: true,
      icon: const Icon(Icons.closed_caption_rounded),
      title: Text(
        leaving
            ? tr('Write a recap before you leave?')
            : tr('Turn off captions?'),
      ),
      content: Text(
        tr(
          'The words from the captions are only on your device and are gone when the call ends. A recap turns them into key points, decisions and to-dos that you can save as a note.',
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('captions-stop-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          key: const ValueKey('captions-stop-only'),
          onPressed: () => Navigator.of(dialogContext).pop(_StopChoice.stop),
          child: Text(leaving ? tr('Just leave') : tr('Turn off')),
        ),
        FilledButton(
          key: const ValueKey('captions-stop-recap'),
          onPressed: () => Navigator.of(dialogContext).pop(_StopChoice.recap),
          child: Text(
            leaving
                ? tr('Write a recap and leave')
                : tr('Turn off and write a recap'),
          ),
        ),
      ],
    ),
  );
}
