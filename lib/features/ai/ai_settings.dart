import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/transcribe/transcribe_controller.dart';
import 'package:wecord/features/transcribe/voice_transcriber.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings → AI: the user's own switch for AI features, and whether the
/// server has AI set up (with today's use of the daily limit).
class AiSettingsGroup extends ConsumerStatefulWidget {
  const AiSettingsGroup({this.showHeader = true, super.key});

  final bool showHeader;

  @override
  ConsumerState<AiSettingsGroup> createState() => _AiSettingsGroupState();
}

class _AiSettingsGroupState extends ConsumerState<AiSettingsGroup> {
  @override
  void initState() {
    super.initState();
    // Today's count may have moved since it was last read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(aiStatusProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(aiStatusProvider);
    final enabled = ref.watch(aiEnabledProvider);
    final info = status.value;
    final configured = info != null;

    final subtitle = switch (status) {
      AsyncData(value: null) => tr(
        "AI isn't set up on this server yet. Whoever runs the server can turn it on (see docs/ai-setup.md).",
      ),
      AsyncError() => tr(
        "Couldn't check whether AI is set up. Try again later.",
      ),
      AsyncLoading() => tr('Checking…'),
      _ => tr(
        'Summaries, rewriting and translation. Only what you ask about is sent to the AI provider.',
      ),
    };

    return SettingsGroup(
      key: const ValueKey('ai-settings'),
      header: widget.showHeader ? tr('AI') : null,
      children: [
        SettingsRow.toggle(
          key: const ValueKey('ai-enabled-switch'),
          icon: Icons.auto_awesome_rounded,
          tone: SettingsTone.accent,
          title: tr('AI features'),
          subtitle: subtitle,
          value: configured && enabled,
          onChanged: configured
              ? (value) =>
                    unawaited(ref.read(aiEnabledProvider.notifier).set(value))
              : null,
        ),
        // Voice messages turn into text on the device itself, so this does
        // not depend on the server's AI. Only where the device can do it.
        if (ref.watch(voiceTranscriberProvider).runsOnDevice)
          SettingsRow.toggle(
            key: const ValueKey('auto-transcribe-switch'),
            icon: Icons.subtitles_outlined,
            tone: SettingsTone.accent,
            title: tr('Auto-transcribe voice messages'),
            subtitle: tr(
              'Voice messages in the chat you have open turn into text on this device. The audio never goes to a server this way.',
            ),
            value: ref.watch(autoTranscribeProvider),
            onChanged: (value) =>
                unawaited(ref.read(autoTranscribeProvider.notifier).set(value)),
          ),
        if (info != null)
          SettingsRow(
            key: const ValueKey('ai-usage-row'),
            icon: Icons.speed_rounded,
            title: tr('Today'),
            subtitle: info.remaining == 0
                ? tr(
                    "You've used all {limit} AI requests for today. It resets tomorrow.",
                    {'limit': info.dailyLimit},
                  )
                : tr('{used} of {limit} requests used today', {
                    'used': info.used,
                    'limit': info.dailyLimit,
                  }),
          ),
      ],
    );
  }
}

/// Circle settings: "Allow AI features in this circle", for members who
/// manage the circle. Off, nobody in the circle gets AI in its chats.
class CircleAiSwitch extends ConsumerStatefulWidget {
  const CircleAiSwitch({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleAiSwitch> createState() => _CircleAiSwitchState();
}

class _CircleAiSwitchState extends ConsumerState<CircleAiSwitch> {
  bool? _pending;

  Future<void> _set(bool enabled) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _pending = enabled);
    try {
      await ref
          .read(aiRepositoryProvider)
          .setCircleAiEnabled(widget.circleId, enabled: enabled);
      ref.invalidate(circleAiEnabledProvider(widget.circleId));
      // Wait for the stored value so the switch does not flick back.
      await ref.read(circleAiEnabledProvider(widget.circleId).future);
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr("Couldn't update AI features. Try again."))),
      );
    } finally {
      if (mounted) {
        setState(() => _pending = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stored =
        ref.watch(circleAiEnabledProvider(widget.circleId)).value ?? true;
    return SettingsGroup(
      key: const ValueKey('circle-ai-settings'),
      header: tr('AI'),
      children: [
        SettingsRow.toggle(
          key: const ValueKey('circle-ai-switch'),
          icon: Icons.auto_awesome_rounded,
          tone: SettingsTone.accent,
          title: tr('Allow AI features in this circle'),
          subtitle: tr(
            "Catch-up summaries, rewriting and translating in this circle's chats. Members can still turn AI off for themselves.",
          ),
          value: _pending ?? stored,
          onChanged: _pending == null
              ? (value) => unawaited(_set(value))
              : null,
        ),
      ],
    );
  }
}
