import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/later/later_cards.dart' show laterPreview;
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/urgent/urgent_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Confirms an urgent message ("Got it") and refreshes what shows it.
Future<void> confirmUrgent(WidgetRef ref, PendingUrgent urgent) async {
  await ref.read(urgentRepositoryProvider).acknowledge(urgent.messageId);
  _refresh(ref, urgent.conversationId);
}

/// Stops urgent messages from [urgent]'s sender (and confirms what is waiting
/// from them).
Future<void> muteUrgentSender(WidgetRef ref, PendingUrgent urgent) async {
  await ref
      .read(urgentRepositoryProvider)
      .setAllowedFrom(urgent.senderId, allowed: false);
  ref.invalidate(mutedUrgentSendersProvider);
  _refresh(ref, urgent.conversationId);
}

void _refresh(WidgetRef ref, String conversationId) {
  ref
    ..invalidate(pendingUrgentsProvider(conversationId))
    ..invalidate(pendingUrgentsProvider(null));
}

/// The red strip at the top of a chat while someone's urgent message waits
/// for the current user: "Ada marked a message urgent", the start of it, and
/// "Got it". Red is for what needs the person (the design language's rule);
/// it goes away once they confirm. Nothing when nothing is waiting.
class UrgentBanner extends ConsumerStatefulWidget {
  const UrgentBanner({
    required this.conversationId,
    required this.onJump,
    this.desktop = false,
    super.key,
  });

  final String conversationId;

  /// Scrolls the chat to the message.
  final ValueChanged<String> onJump;
  final bool desktop;

  @override
  ConsumerState<UrgentBanner> createState() => _UrgentBannerState();
}

class _UrgentBannerState extends ConsumerState<UrgentBanner> {
  var _busy = false;

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      await action();
      if (done != null) {
        messenger?.showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Something went wrong. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting =
        ref.watch(pendingUrgentsProvider(widget.conversationId)).value ??
        const <PendingUrgent>[];
    if (waiting.isEmpty) {
      return const SizedBox.shrink();
    }
    final urgent = waiting.first;
    final more = waiting.length - 1;
    final c = context.tokens.colors;
    final name = urgent.senderName.isEmpty ? tr('Someone') : urgent.senderName;
    final preview = laterPreview(
      conversationId: urgent.conversationId,
      body: urgent.body,
      type: urgent.type,
    );
    return Container(
      key: const ValueKey('urgent-banner'),
      width: double.infinity,
      margin: widget.desktop
          ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
          : const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.dangerSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
            child: ExcludeSemantics(
              child: Icon(
                Icons.priority_high_rounded,
                size: 18,
                color: c.onDanger,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(
                    more > 0
                        ? tr('{name} marked a message urgent · {count} more', {
                            'name': name,
                            'count': more,
                          })
                        : tr('{name} marked a message urgent', {'name': name}),
                    key: const ValueKey('urgent-banner-title'),
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: c.dangerText,
                    ),
                  ),
                ),
                if (preview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: c.ink,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    WeCordButton(
                      key: const ValueKey('urgent-got-it'),
                      label: tr('Got it'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.danger,
                      loading: _busy,
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                              _run(() => confirmUrgent(ref, urgent)),
                            ),
                    ),
                    WeCordButton(
                      key: const ValueKey('urgent-jump'),
                      label: tr('Jump'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.secondary,
                      onPressed: () => widget.onJump(urgent.messageId),
                    ),
                    WeCordButton(
                      key: const ValueKey('urgent-turn-off'),
                      label: tr('Turn off for {name}', {'name': name}),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                              _run(
                                () => muteUrgentSender(ref, urgent),
                                done: tr(
                                  'Urgent messages from {name} are off. You can turn them back on in Settings.',
                                  {'name': name},
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
