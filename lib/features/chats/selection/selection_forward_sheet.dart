import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_repository.dart';
import 'package:wecord/features/chats/selection/selection_rules.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How selected messages are forwarded.
enum SelectionForwardMode {
  /// Each message on its own, like the message menu's Forward.
  oneByOne,

  /// All of them as one "Chat history" message.
  merged,
}

/// Picks the chat the selected [messages] (oldest first) go to and sends
/// them. Pops true once they are sent.
Future<bool?> showSelectionForwardSheet(
  BuildContext context, {
  required List<ChatMessage> messages,
  required SelectionForwardMode mode,
  required String conversationTitle,
}) {
  return showWeCordSheet<bool>(
    context,
    title: mode == SelectionForwardMode.merged
        ? tr('Merge & forward to')
        : tr('Forward to'),
    builder: (context, _) => SelectionForwardSheet(
      messages: messages,
      mode: mode,
      conversationTitle: conversationTitle,
    ),
  );
}

class SelectionForwardSheet extends ConsumerStatefulWidget {
  const SelectionForwardSheet({
    required this.messages,
    required this.mode,
    required this.conversationTitle,
    super.key,
  });

  final List<ChatMessage> messages;
  final SelectionForwardMode mode;

  /// The name of the chat the messages are from: the title of a merged
  /// forward.
  final String conversationTitle;

  @override
  ConsumerState<SelectionForwardSheet> createState() =>
      _SelectionForwardSheetState();
}

class _SelectionForwardSheetState extends ConsumerState<SelectionForwardSheet> {
  var _query = '';
  var _isForwarding = false;
  String? _errorText;

  bool get _merged => widget.mode == SelectionForwardMode.merged;

  List<ChatMessage> get _forwardable => [
    for (final message in widget.messages)
      if (canForwardMessage(message)) message,
  ];

  Future<void> _forwardTo(String conversationId) async {
    setState(() {
      _isForwarding = true;
      _errorText = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final messages = _forwardable;
    try {
      if (_merged) {
        await ref
            .read(mergedForwardRepositoryProvider)
            .forwardMerged(
              sourceMessageIds: [for (final message in messages) message.id],
              targetConversationId: conversationId,
              title: widget.conversationTitle,
            );
      } else {
        final repository = ref.read(chatsRepositoryProvider);
        for (final message in messages) {
          await repository.forwardMessage(
            sourceMessageId: message.id,
            targetConversationId: conversationId,
          );
        }
      }
      ref.invalidate(conversationsProvider);
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _merged
                ? tr('Chat history sent')
                : messages.length == 1
                ? tr('Message forwarded')
                : tr('{count} messages forwarded', {'count': messages.length}),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isForwarding = false;
        _errorText =
            error is SendRefusedException || error is MergedForwardException
            ? error.toString()
            : tr('Could not forward messages. Try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final conversations = ref.watch(conversationsProvider);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final skipped = widget.messages.length - _forwardable.length;
    final note = _merged
        ? (_forwardable.length == 1
              ? tr('1 message will be sent as one chat history.')
              : tr('{count} messages will be sent as one chat history.', {
                  'count': _forwardable.length,
                }))
        : null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.min(
              600,
              (MediaQuery.sizeOf(context).height - keyboard) * 0.85,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (note != null || skipped > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    [
                      ?note,
                      if (skipped > 0)
                        skipped == 1
                            ? tr(
                                '1 message cannot be forwarded and is left out.',
                              )
                            : tr(
                                '{count} messages cannot be forwarded and are left out.',
                                {'count': skipped},
                              ),
                    ].join(' '),
                    key: const ValueKey('selection-forward-note'),
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: c.muted,
                    ),
                  ),
                ),
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
                    onChanged: (value) => setState(() => _query = value),
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
                      SheetNote(text: error.toString(), error: true),
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
    final sourceId = widget.messages.firstOrNull?.conversationId;
    final visible = [
      for (final conversation in conversations)
        if (conversation.id != sourceId &&
            !conversation.isThread &&
            // Chat history goes to direct chats and groups only.
            (!_merged || conversation.isDirectMessage) &&
            (normalizedQuery.isEmpty ||
                (conversation.title?.toLowerCase().contains(normalizedQuery) ??
                    false)))
          conversation,
    ];

    if (visible.isEmpty) {
      return SheetNote(text: tr('No matching conversations'));
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final conversation = visible[index];
        final title = conversation.title?.trim().isNotEmpty == true
            ? conversation.title!.trim()
            : tr('Conversation');
        final group = conversation.type != ConversationType.direct;
        return SheetListRow(
          key: ValueKey('forward-target-${conversation.id}'),
          enabled: !_isForwarding && _forwardable.isNotEmpty,
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
          onTap: () => unawaited(_forwardTo(conversation.id)),
        );
      },
    );
  }
}
