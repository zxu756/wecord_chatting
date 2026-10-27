import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/on_device/on_device_ai.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings → AI → "Prefer on-device AI" (roadmap F8), only where the
/// platform can have a model of its own (the iPhone and Mac apps; see
/// [OnDeviceAiBackend.isSupportedPlatform]). On a device that can't run it,
/// the row says so and AI keeps using the server.
class OnDeviceAiRow extends ConsumerWidget {
  const OnDeviceAiRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(onDeviceAiStatusProvider);
    final prefer = ref.watch(preferOnDeviceAiProvider);
    final reason = status.value?.reason;
    // A device that will never run it can't switch it on.
    final never = reason != null && !reason.canChange;
    final subtitle = switch (status) {
      AsyncLoading() => tr('Checking…'),
      AsyncError() => onDeviceAiReasonText(OnDeviceAiUnavailable.unknown),
      _ =>
        reason == null
            ? tr(
                "Summaries, rewriting and translation run on this device when they can, so the text never leaves it and doesn't count against today's limit. When this device can't, the server does them.",
              )
            : onDeviceAiReasonText(reason),
    };
    return SettingsRow.toggle(
      key: const ValueKey('on-device-ai-switch'),
      icon: Icons.phonelink_lock_rounded,
      tone: SettingsTone.accent,
      title: tr('Prefer on-device AI'),
      subtitle: subtitle,
      value: prefer && !never,
      onChanged: never
          ? null
          : (value) => unawaited(
              ref.read(preferOnDeviceAiProvider.notifier).set(value),
            ),
    );
  }
}

/// What to tell the person about why the device's own model isn't in use.
String onDeviceAiReasonText(OnDeviceAiUnavailable reason) {
  return switch (reason) {
    OnDeviceAiUnavailable.unsupportedPlatform => tr(
      "This device can't run AI on its own. AI uses the server.",
    ),
    OnDeviceAiUnavailable.osTooOld => tr(
      'On-device AI needs iOS 26 or macOS 26 or later. Until then, AI uses the server.',
    ),
    OnDeviceAiUnavailable.deviceNotEligible => tr(
      "This device doesn't support Apple Intelligence, so AI uses the server.",
    ),
    OnDeviceAiUnavailable.notEnabled => tr(
      'Turn on Apple Intelligence in the system Settings to use it. Until then, AI uses the server.',
    ),
    OnDeviceAiUnavailable.modelNotReady => tr(
      "The on-device model isn't ready yet. Until it is, AI uses the server.",
    ),
    OnDeviceAiUnavailable.unknown => tr(
      "The on-device model isn't available right now. AI uses the server.",
    ),
  };
}
