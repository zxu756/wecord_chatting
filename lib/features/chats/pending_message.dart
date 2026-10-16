import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/send_failure.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A message the server has not stored yet: the bubble, faded and without
/// its actions, over "Sending…" or "Failed — tap to retry". When the
/// server said why it refused an attachment ([reason]), that shows
/// instead, with "Edit and resend" and "Discard" for a refusal that
/// sending again would not change. A slowmode refusal counts its wait down
/// live and offers "Retry" once it is over.
class PendingMessageFrame extends StatelessWidget {
  const PendingMessageFrame({
    required this.entry,
    required this.onRetry,
    required this.onDiscard,
    required this.child,
    this.alignEnd = true,
    this.reason,
    this.onEditResend,
    this.now,
    super.key,
  });

  final OutboxEntry entry;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;
  final Widget child;

  /// Own messages sit on the right in bubble chats.
  final bool alignEnd;

  /// Why the server refused it, if it said (see [sendFailureReason]).
  final String? reason;

  /// Puts an attachment's files back in the tray, to change and send again.
  final VoidCallback? onEditResend;

  /// The time to count a slowmode wait against; the clock by default.
  final DateTime Function()? now;

  /// When the slowmode wait of a failed [entry] ends, if it has one.
  DateTime? get _slowmodeEnd {
    final error = entry.error;
    final failedAt = entry.failedAt;
    if (entry.state != OutboxState.failed ||
        error is! SlowmodeException ||
        failedAt == null) {
      return null;
    }
    return failedAt.add(Duration(seconds: error.remainingSeconds));
  }

  @override
  Widget build(BuildContext context) {
    final end = _slowmodeEnd;
    if (end == null) {
      return _frame(context, reason: reason);
    }
    return _Countdown(
      end: end,
      now: now ?? (() => clock.now()),
      builder: (context, left) => _frame(
        context,
        reason: left > 0
            ? SlowmodeException(left).toString()
            : tr('Slowmode is over. You can send it now.'),
        waiting: left > 0,
      ),
    );
  }

  Widget _frame(
    BuildContext context, {
    required String? reason,
    bool waiting = false,
  }) {
    final c = context.tokens.colors;
    final failed = entry.state == OutboxState.failed;
    final editResend = onEditResend;
    final refused =
        failed &&
        entry.media != null &&
        editResend != null &&
        !isRetryableFailure(entry.error);
    final status = failed && (reason != null || refused)
        ? _failureStatus(
            context,
            reason: reason,
            canRetry: !refused && !waiting,
            onEditResend: editResend,
            waiting: waiting,
          )
        : failed
        ? WeCordPressable(
            key: ValueKey('pending-retry-${entry.clientId}'),
            onPressed: onRetry,
            onLongPress: onDiscard,
            semanticLabel: tr('Failed — tap to retry'),
            builder: (context, states) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: c.danger),
                const SizedBox(width: 4),
                Text(
                  tr('Failed — tap to retry'),
                  style: TextStyle(
                    color: c.dangerText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        : Row(
            key: ValueKey('pending-sending-${entry.clientId}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.schedule_rounded, size: 13, color: c.faint),
              const SizedBox(width: 4),
              Text(
                tr('Sending…'),
                style: TextStyle(
                  color: c.subtle,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Attachments show their own progress, cancel and retry buttons, so
        // they stay at full strength and tappable.
        if (entry.media != null)
          child
        else
          IgnorePointer(
            child: Opacity(opacity: failed ? 0.55 : 0.7, child: child),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
          child: status,
        ),
      ],
    );
  }

  /// Says why it failed, over the buttons that fit: "Retry" while sending
  /// again could work, else "Edit and resend", and always "Discard".
  Widget _failureStatus(
    BuildContext context, {
    required String? reason,
    required bool canRetry,
    required VoidCallback? onEditResend,
    bool waiting = false,
  }) {
    final c = context.tokens.colors;
    Widget action(String key, String label, VoidCallback onPressed) {
      return WeCordPressable(
        key: ValueKey('$key-${entry.clientId}'),
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, states) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text(
            label,
            style: TextStyle(
              color: c.accent,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      key: ValueKey('pending-failed-${entry.clientId}'),
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 14,
                  color: c.danger,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  reason ?? tr('Failed to send'),
                  key: ValueKey('pending-reason-${entry.clientId}'),
                  textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                  style: TextStyle(
                    color: c.dangerText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 14,
            children: [
              if (canRetry)
                action('pending-retry', tr('Retry'), onRetry)
              else if (!waiting && onEditResend != null)
                action(
                  'pending-edit-resend',
                  tr('Edit and resend'),
                  onEditResend,
                ),
              action('pending-discard', tr('Discard'), onDiscard),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rebuilds [builder] every second with the whole seconds left until [end]
/// (0 once it has passed), then stops.
class _Countdown extends StatefulWidget {
  const _Countdown({
    required this.end,
    required this.now,
    required this.builder,
  });

  final DateTime end;
  final DateTime Function() now;
  final Widget Function(BuildContext context, int secondsLeft) builder;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _ticker;

  int get _left {
    final ms = widget.end.difference(widget.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.end != widget.end) {
      _sync();
    }
  }

  void _sync() {
    _ticker?.cancel();
    _ticker = null;
    if (_left == 0) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (_left == 0) {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _left);
}
