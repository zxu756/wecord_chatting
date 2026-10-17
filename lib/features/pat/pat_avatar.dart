import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/pat/pat_info.dart';
import 'package:wecord/features/pat/pat_repository.dart';
import 'package:wecord/features/pat/pat_shake.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A pat that just arrived for the current user: which line, from whom, when.
typedef IncomingPat = ({String messageId, String actorId, DateTime createdAt});

/// How old an incoming pat can be and still shake an avatar: the shake is
/// for pats that happen while the chat is open.
const incomingPatFreshness = Duration(seconds: 15);

/// The newest pat in [conversationId] aimed at the current user that was not
/// taken back; null when there is none.
final incomingPatProvider = Provider.autoDispose.family<IncomingPat?, String>((
  ref,
  conversationId,
) {
  final me = ref.watch(authStateProvider.select((a) => a.value?.id));
  final messages = ref.watch(
    chatThreadProvider(conversationId).select((a) => a.value?.messages),
  );
  if (me == null || messages == null) {
    return null;
  }
  for (final message in messages.reversed) {
    final pat = patOf(message);
    if (pat != null && pat.targetId == me && !pat.undone) {
      return (
        messageId: message.id,
        actorId: pat.actorId,
        createdAt: message.createdAt,
      );
    }
  }
  return null;
});

/// Whether avatars in [conversationId] can be patted, and whether the chat
/// is muted: pats are for direct and group chats (never circle channels or
/// threads), and a muted chat gets the line but no shake.
typedef PatChatInfo = ({bool eligible, bool muted});

final patChatInfoProvider = Provider.autoDispose.family<PatChatInfo, String>((
  ref,
  conversationId,
) {
  final conversation = ref.watch(
    conversationsProvider.select(
      (list) => list.value
          ?.where((conversation) => conversation.id == conversationId)
          .firstOrNull,
    ),
  );
  if (conversation == null) {
    // Not in the list (yet): a chat the user just opened.
    return (eligible: true, muted: false);
  }
  return (
    eligible:
        conversation.circleId == null &&
        !conversation.isNoteToSelf &&
        (conversation.type == ConversationType.direct ||
            conversation.type == ConversationType.group),
    muted: conversation.isMuted,
  );
});

/// Pats [userId] in [conversationId]: a light tap, the avatar shakes at
/// once, and the server adds the line to the chat. Too many pats, a blocked
/// person and the like are said in a snackbar.
Future<void> patUser(
  BuildContext context,
  WidgetRef ref, {
  required String conversationId,
  required String userId,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  WeCordHaptics.light();
  ref.read(patShakeProvider(conversationId).notifier).shake(userId);
  try {
    await ref
        .read(patRepositoryProvider)
        .pat(conversationId: conversationId, userId: userId);
  } on PatException catch (error) {
    messenger?.showSnackBar(
      SnackBar(
        content: Text(switch (error.failure) {
          PatFailure.tooFast => tr(
            'You just patted them. Try again in a moment.',
          ),
          PatFailure.tooMany => tr('That is a lot of pats. Try again later.'),
          PatFailure.notAllowed => tr("You can't pat them here."),
          _ => tr("Couldn't pat. Try again."),
        }),
      ),
    );
  } on Object {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr("Couldn't pat. Try again."))),
    );
  }
}

/// Makes the avatar [child] of [userId] in a chat pattable: double tap (or
/// double click) pats them, and the avatar shakes gently when they pat, or
/// are patted by, the current user. Anyone else's avatars, and avatars in
/// circles, are left as they are.
class PatAvatar extends ConsumerStatefulWidget {
  const PatAvatar({
    required this.conversationId,
    required this.userId,
    required this.name,
    required this.child,
    super.key,
  });

  final String conversationId;

  /// Whose avatar it is; null (a webhook, an unknown sender) is not pattable.
  final String? userId;
  final String name;
  final Widget child;

  @override
  ConsumerState<PatAvatar> createState() => _PatAvatarState();
}

class _PatAvatarState extends ConsumerState<PatAvatar> {
  var _shakes = 0;

  void _shake() {
    if (mounted) {
      setState(() => _shakes++);
    }
  }

  void _pat() {
    final userId = widget.userId;
    if (userId == null) {
      return;
    }
    unawaited(
      patUser(
        context,
        ref,
        conversationId: widget.conversationId,
        userId: userId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = widget.userId;
    final me = ref.watch(authStateProvider.select((a) => a.value?.id));
    final info = ref.watch(patChatInfoProvider(widget.conversationId));
    if (userId == null || me == null || userId == me || !info.eligible) {
      return widget.child;
    }
    // My own tap, shaking the person I patted.
    ref.listen(patShakeProvider(widget.conversationId), (previous, next) {
      if (next != null && next.userId == userId) {
        _shake();
      }
    });
    // Someone patting me: their avatar shakes, unless the chat is muted.
    ref.listen(incomingPatProvider(widget.conversationId), (previous, next) {
      if (next == null ||
          next.messageId == previous?.messageId ||
          next.actorId != userId ||
          info.muted) {
        return;
      }
      if (clock.now().toUtc().difference(next.createdAt.toUtc()) <=
          incomingPatFreshness) {
        _shake();
      }
    });
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: tr('Pat {name}', {'name': widget.name})):
            _pat,
      },
      child: GestureDetector(
        key: ValueKey('pat-avatar-$userId'),
        behavior: HitTestBehavior.opaque,
        onDoubleTap: _pat,
        child: PatShake(trigger: _shakes, child: widget.child),
      ),
    );
  }
}
