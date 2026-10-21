import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Picks a chat to forward [message] to, inside a WeCord sheet titled
/// "Forward to": a search field and the user's direct and group chats.
class MessageForwardSheet extends ConsumerStatefulWidget {
  const MessageForwardSheet({required this.message, super.key});

  final ChatMessage message;

  @override
  ConsumerState<MessageForwardSheet> createState() =>
      _MessageForwardSheetState();
}

class _MessageForwardSheetState extends ConsumerState<MessageForwardSheet> {
  var _query = '';
  var _isForwarding = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final conversations = ref.watch(listedConversationsProvider);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(
              560,
              (MediaQuery.sizeOf(context).height - keyboard) * 0.8,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Semantics(
                  label: tr('Search chats'),
                  textField: true,
                  child: WeCordTextField(
                    fieldKey: const ValueKey('forward-search'),
                    autofocus: true,
                    hint: tr('Search chats'),
                    prefixIcon: Icons.search_rounded,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                  ),
                ),
              ),
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Text(
                    _errorText!,
                    style: TextStyle(fontSize: 13.5, color: c.dangerText),
                  ),
                ),
              Flexible(
                child: conversations.when(
                  loading: () => const SheetSpinner(),
                  error: (error, stackTrace) =>
                      SheetNote(text: errorText(error), error: true),
                  data: _buildConversationList,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConversationList(List<ConversationSummary> conversations) {
    final normalizedQuery = _query.trim().toLowerCase();
    final visibleConversations = conversations
        .where((conversation) {
          if (conversation.id == widget.message.conversationId ||
              conversation.isThread) {
            return false;
          }
          if (normalizedQuery.isEmpty) {
            return true;
          }
          return conversation.title?.toLowerCase().contains(normalizedQuery) ??
              false;
        })
        .toList(growable: false);

    if (visibleConversations.isEmpty) {
      return SheetNote(text: tr('No matching conversations'));
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: visibleConversations.length,
      itemBuilder: (context, index) {
        final conversation = visibleConversations[index];
        final title = conversation.title?.trim().isNotEmpty == true
            ? conversation.title!.trim()
            : tr('Conversation');
        final group = conversation.type != ConversationType.direct;
        return SheetListRow(
          key: ValueKey('forward-target-${conversation.id}'),
          enabled: !_isForwarding,
          leading: ResolvedAvatar(
            name: title,
            avatarUrl: conversation.avatarUrl,
            size: 40,
            squircle: group,
          ),
          title: title,
          subtitle: switch (conversation.type) {
            ConversationType.group => tr('Group'),
            ConversationType.channel => tr('Channel'),
            _ => tr('Direct'),
          },
          trailing: Icon(
            Icons.send_rounded,
            size: 18,
            color: context.tokens.colors.faint,
          ),
          onTap: () => _forwardToConversation(conversation.id),
        );
      },
    );
  }

  Future<void> _forwardToConversation(String conversationId) async {
    setState(() {
      _isForwarding = true;
      _errorText = null;
    });
    final repository = ref.read(chatsRepositoryProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await repository.forwardMessage(
        sourceMessageId: widget.message.id,
        targetConversationId: conversationId,
      );
      ref.invalidate(conversationsProvider);
      if (!mounted) {
        return;
      }
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(tr('Message forwarded'))));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isForwarding = false;
        _errorText = error is SendRefusedException
            ? error.toString()
            : tr('Could not forward message. Try again.');
      });
    }
  }
}
