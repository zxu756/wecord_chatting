import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Shown in a search box after the secret code was typed: the chats that are
/// hidden from the list, each opening behind the lock, and a button that hides
/// them again. Nothing when the code was not typed.
class HiddenChatsSection extends ConsumerWidget {
  const HiddenChatsSection({super.key});

  static const sectionKey = ValueKey('hidden-chats-section');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(
      chatLockProvider.select((state) => state.hideLocked && state.revealed),
    );
    if (!shown) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final locked = ref.watch(lockedConversationIdsProvider);
    final conversations =
        ref.watch(conversationsProvider).value ?? const <ConversationSummary>[];
    final hidden = [
      for (final conversation in conversations)
        if (locked.contains(conversation.id)) conversation,
    ];
    return Padding(
      key: sectionKey,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    tr('Hidden chats'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.muted,
                    ),
                  ),
                ),
              ),
              WeCordButton(
                key: const ValueKey('hidden-chats-hide-again'),
                label: tr('Hide again'),
                variant: WeCordButtonVariant.ghost,
                size: WeCordButtonSize.small,
                onPressed: () =>
                    ref.read(chatLockProvider.notifier).hideAgain(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (hidden.isEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                tr('No hidden chats.'),
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
            )
          else
            // Never more than a third of the screen: the search under it
            // keeps its room at large text sizes.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.3,
              ),
              child: SingleChildScrollView(
                child: SettingsGroup(
                  children: [
                    for (final conversation in hidden)
                      SettingsRow(
                        key: ValueKey('hidden-chat-${conversation.id}'),
                        icon: Icons.lock_rounded,
                        title: conversation.title?.trim().isNotEmpty == true
                            ? conversation.title!
                            : tr('Conversation'),
                        onTap: () => openConversation(context, conversation),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
