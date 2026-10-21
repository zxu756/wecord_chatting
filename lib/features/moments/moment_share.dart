import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart'
    show SendRefusedException;
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/moments/moments_repository.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Picks a chat to send a card of the Moment [postId] to. The card holds only
/// the Moment's id: whoever opens the chat sees the Moment if they may see it,
/// and "Can't view this Moment" if not.
Future<bool?> showMomentSharePicker(BuildContext context, String postId) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Send to'),
    builder: (context, _) => MomentSharePicker(postId: postId),
  );
}

class MomentSharePicker extends ConsumerStatefulWidget {
  const MomentSharePicker({required this.postId, super.key});

  final String postId;

  @override
  ConsumerState<MomentSharePicker> createState() => _MomentSharePickerState();
}

class _MomentSharePickerState extends ConsumerState<MomentSharePicker> {
  var _query = '';
  var _sending = false;
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
                    fieldKey: const ValueKey('moment-share-search'),
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
                    key: const ValueKey('moment-share-error'),
                    style: TextStyle(fontSize: 13.5, color: c.dangerText),
                  ),
                ),
              Flexible(
                child: conversations.when(
                  loading: () => const SheetSpinner(),
                  error: (error, stackTrace) =>
                      SheetNote(text: errorText(error), error: true),
                  data: _list,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(List<ConversationSummary> conversations) {
    final query = _query.trim().toLowerCase();
    final shown = [
      for (final conversation in conversations)
        if (!conversation.isThread &&
            (query.isEmpty ||
                (conversation.title?.toLowerCase().contains(query) ?? false)))
          conversation,
    ];
    if (shown.isEmpty) {
      return SheetNote(text: tr('No matching conversations'));
    }
    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      itemCount: shown.length,
      itemBuilder: (context, index) {
        final conversation = shown[index];
        final title = conversation.title?.trim().isNotEmpty == true
            ? conversation.title!.trim()
            : tr('Conversation');
        final group = conversation.type != ConversationType.direct;
        return SheetListRow(
          key: ValueKey('moment-share-target-${conversation.id}'),
          enabled: !_sending,
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
          onTap: () => _send(conversation.id),
        );
      },
    );
  }

  Future<void> _send(String conversationId) async {
    setState(() {
      _sending = true;
      _errorText = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(momentsRepositoryProvider)
          .sendMomentCard(
            conversationId: conversationId,
            postId: widget.postId,
          );
      ref.invalidate(conversationsProvider);
      if (!mounted) {
        return;
      }
      navigator.pop(true);
      messenger?.showSnackBar(SnackBar(content: Text(tr('Moment sent'))));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sending = false;
        _errorText = error is SendRefusedException
            ? error.toString()
            : tr('Could not send the Moment. Try again.');
      });
    }
  }
}
