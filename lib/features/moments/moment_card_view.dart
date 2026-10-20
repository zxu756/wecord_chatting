import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/moments/moments_models.dart';
import 'package:wecord/features/moments/moments_providers.dart';
import 'package:wecord/features/moments/moments_screen.dart';
import 'package:wecord/features/moments/moments_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The attachment kind of a Moment shared into a chat (migration
/// 202610260640): `{kind: 'moment_card', post_id}` and nothing else. What it
/// shows is read when the chat is opened, for whoever opens it.
const momentCardKind = 'moment_card';

extension MomentCardMessage on ChatMessage {
  /// The id of the Moment this message is a card of, or null.
  String? get momentCardPostId {
    if (type != MessageType.text || recalledAt != null) {
      return null;
    }
    final attachment = this.attachment;
    if (attachment == null || attachment['kind'] != momentCardKind) {
      return null;
    }
    final id = attachment['post_id'];
    return id is String && id.isNotEmpty ? id : null;
  }
}

/// A Moment in a chat: who posted it and the start of it, as the reader may
/// see it. A reader who may not (the audience leaves them out, they are not
/// friends, the post is gone) sees "Can't view this Moment" and nothing of
/// it. A tap opens the Moment.
class MomentCardView extends ConsumerWidget {
  const MomentCardView({required this.postId, super.key});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final info = ref.watch(momentCardProvider(postId));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 260.0,
          260.0,
        );
        Widget frame({
          required Widget child,
          VoidCallback? onPressed,
          String? label,
          String? hint,
        }) {
          return SizedBox(
            width: width,
            child: WeCordPressable(
              key: ValueKey('moment-card-$postId'),
              onPressed: onPressed,
              semanticLabel: label,
              hint: hint,
              mergeSemantics: false,
              pressedScale: 0.99,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              builder: (context, states) => Container(
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                  border: Border.all(
                    color:
                        states.contains(WidgetState.hovered) &&
                            onPressed != null
                        ? c.faint
                        : c.line,
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: child,
              ),
            ),
          );
        }

        Widget footer(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            children: [
              Container(height: 1, color: c.lineSoft),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: c.subtle),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.subtle),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        return info.when(
          loading: () => frame(
            label: tr('Moment'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(
                  height: 48,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                footer(Icons.auto_awesome_motion_outlined, tr('Moment')),
              ],
            ),
          ),
          error: (error, stackTrace) => _unavailable(frame, footer, c),
          data: (card) {
            if (card == null) {
              return _unavailable(frame, footer, c);
            }
            final excerpt = card.excerpt.trim();
            final summary = excerpt.isNotEmpty
                ? excerpt
                : switch (card.kind) {
                    MomentKind.photos => tr('Photos'),
                    MomentKind.video => tr('Video'),
                    MomentKind.link => tr('Link'),
                    MomentKind.text => '',
                  };
            return frame(
              onPressed: () =>
                  unawaited(context.push('${MomentsScreen.path}/$postId')),
              label: summary.isEmpty
                  ? tr('Moment from {name}', {'name': card.authorName})
                  : tr('Moment from {name}: {text}', {
                      'name': card.authorName,
                      'text': summary,
                    }),
              hint: tr('Opens the Moment'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              card.authorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: c.ink,
                              ),
                            ),
                            if (summary.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  summary,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.35,
                                    color: c.muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (card.thumb != null) ...[
                        const SizedBox(width: 10),
                        ExcludeSemantics(
                          child: SizedBox.square(
                            dimension: 56,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                WeCordRadii.sm,
                              ),
                              child: MomentImage(path: card.thumb!),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  footer(Icons.auto_awesome_motion_outlined, tr('Moment')),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _unavailable(
    Widget Function({
      required Widget child,
      VoidCallback? onPressed,
      String? label,
      String? hint,
    })
    frame,
    Widget Function(IconData, String) footer,
    WeCordPalette c,
  ) {
    return frame(
      label: tr("Can't view this Moment"),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 20, color: c.subtle),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr("Can't view this Moment"),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.muted,
                  ),
                ),
              ),
            ],
          ),
          footer(Icons.auto_awesome_motion_outlined, tr('Moment')),
        ],
      ),
    );
  }
}
