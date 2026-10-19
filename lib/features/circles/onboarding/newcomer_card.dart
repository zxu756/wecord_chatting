import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/circles/onboarding/guide_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Ada joined the circle", with a button that says hello back: the system
/// message a circle's greeting channel gets for each new member (see
/// `202610230220_onboarding_greeting.sql`).
///
/// "Say hello" sends the circle's greeting sticker, or a waving hand when it
/// has none, through the ordinary send paths: slowmode, AutoMod and the
/// channel's permissions all apply. It is not offered on one's own card.
class NewcomerCard extends ConsumerStatefulWidget {
  const NewcomerCard({
    required this.conversationId,
    required this.notice,
    super.key,
  });

  final String conversationId;
  final NewcomerNotice notice;

  @override
  ConsumerState<NewcomerCard> createState() => _NewcomerCardState();
}

class _NewcomerCardState extends ConsumerState<NewcomerCard> {
  var _sending = false;
  var _greeted = false;

  Future<void> _sayHello() async {
    setState(() => _sending = true);
    final chats = ref.read(chatsRepositoryProvider);
    final name = widget.notice.userLabel;
    try {
      final stickerId = widget.notice.stickerId;
      if (stickerId != null) {
        try {
          await chats.sendSticker(
            conversationId: widget.conversationId,
            stickerId: stickerId,
          );
          if (mounted) {
            setState(() => _greeted = true);
          }
          return;
        } on Object {
          // The sticker may be gone; fall back to the hand.
        }
      }
      await chats.sendTextMessage(
        conversationId: widget.conversationId,
        body: tr('Welcome, {name}! 👋', {'name': name}),
      );
      if (mounted) {
        setState(() => _greeted = true);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not say hello. Try again.'))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final currentUserId = ref.watch(authRepositoryProvider).currentUser?.id;
    final ownCard = currentUserId == widget.notice.userId;
    final name = widget.notice.userLabel.isEmpty
        ? tr('Someone')
        : widget.notice.userLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            key: const ValueKey('newcomer-card'),
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.waving_hand_rounded, size: 20, color: c.accentText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr('{name} joined the circle', {'name': name}),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.accentText,
                    ),
                  ),
                ),
                if (!ownCard) ...[
                  const SizedBox(width: 8),
                  if (_greeted)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.check_rounded,
                        key: const ValueKey('newcomer-greeted'),
                        semanticLabel: tr('Greeted'),
                        size: 20,
                        color: c.accentText,
                      ),
                    )
                  else
                    WeCordButton(
                      key: const ValueKey('newcomer-say-hello'),
                      label: tr('Say hello'),
                      variant: WeCordButtonVariant.accent,
                      size: WeCordButtonSize.small,
                      loading: _sending,
                      onPressed: _sending ? null : () => unawaited(_sayHello()),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
