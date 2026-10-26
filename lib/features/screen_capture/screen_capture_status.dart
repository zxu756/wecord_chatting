import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/screen_capture/screen_capture_service.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What this device can and cannot tell about screenshots, in plain words
/// (roadmap G7). Shown wherever the app talks about screenshot alerts, so
/// nobody takes an alert that cannot come for a promise.
String screenCaptureStatusText({required bool detects}) {
  if (detects) {
    return tr(
      'This iPhone or iPad tells WeCord when you take a screenshot or record '
      'the screen while a view-once photo or video is open, and the sender is '
      'told. Alerts are best effort: they come after the fact, and they are '
      'not a promise that nobody kept a copy.',
    );
  }
  return tr(
    'This device cannot tell when a screenshot is taken or the screen is '
    'recorded, so it sends no alerts and cannot warn you about others on it. '
    'Only iPhone and iPad can. A view-once photo you open here may be kept '
    'without the sender knowing.',
  );
}

/// What a person who sends a view-once photo or video should know about
/// alerts, whatever device they use.
String screenCaptureSenderNote() => tr(
  'You are told when a screenshot or screen recording is noticed on an '
  'iPhone or iPad. Computers, the web and other phones cannot be noticed, so '
  'no alert is not proof that nobody kept a copy.',
);

/// The device's screenshot status as a card: a title and the words above.
class ScreenCaptureStatusCard extends ConsumerWidget {
  const ScreenCaptureStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final detects = ref.watch(screenCaptureDetectsProvider);
    return Container(
      key: const ValueKey('screen-capture-status'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: detects ? c.successSoft : c.warningSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            detects
                ? Icons.screenshot_monitor_rounded
                : Icons.visibility_off_outlined,
            size: 20,
            color: detects ? c.successText : c.warningText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detects
                      ? tr('Screenshot alerts work on this device')
                      : tr('Screenshot alerts do not work on this device'),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  screenCaptureStatusText(detects: detects),
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: c.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
