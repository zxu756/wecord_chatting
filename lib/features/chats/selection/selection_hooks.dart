import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/selection/selection_controller.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// The "Select" entry of a message's menu: enters selection mode with
/// the message ticked.
MessageAction selectMessageAction(BuildContext context, ChatMessage message) {
  final container = ProviderScope.containerOf(context, listen: false);
  return MessageAction(
    key: const ValueKey('message-select'),
    icon: Icons.checklist_rounded,
    label: tr('Select'),
    onSelected: () => container
        .read(chatSelectionProvider(message.conversationId).notifier)
        .begin(message),
  );
}

/// Around the whole chat: Esc leaves selection mode (on desktop and the
/// web; also with a hardware keyboard on a tablet). Takes the keyboard
/// focus when selection starts, because the composer that had it goes.
class ChatSelectionKeyboard extends ConsumerStatefulWidget {
  const ChatSelectionKeyboard({
    required this.conversationId,
    required this.child,
    super.key,
  });

  final String conversationId;
  final Widget child;

  @override
  ConsumerState<ChatSelectionKeyboard> createState() =>
      _ChatSelectionKeyboardState();
}

class _ChatSelectionKeyboardState extends ConsumerState<ChatSelectionKeyboard> {
  final _focus = FocusNode(debugLabel: 'chat selection', skipTraversal: true);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = chatSelectionProvider(widget.conversationId);
    ref.listen(provider.select((state) => state.active), (previous, active) {
      if (active && previous != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ref.read(provider).active) {
            _focus.requestFocus();
          }
        });
      }
    });
    return Focus(
      focusNode: _focus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            ref.read(provider).active) {
          ref.read(provider.notifier).cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }
}
