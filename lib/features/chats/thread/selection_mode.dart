part of '../chat_thread_screen.dart';

// Selection mode: what replaces the header and the composer while the reader
// chooses messages (the choosing itself lives in chats/selection/).

extension _ThreadSelectionMode on _ChatThreadScreenState {
  /// The header while choosing messages.
  Widget _selectionHeader(_ThreadFacts f) {
    return ChatSelectionHeader(
      conversationId: widget.conversationId,
      desktop: f.desktop,
    );
  }

  /// The bar that takes the composer's place while choosing messages.
  Widget _selectionBar(_ThreadFacts f) {
    final _ThreadFacts(
      :title,
      :currentUserId,
      :canDeleteAsModerator,
      :groupDetail,
      :desktop,
      :composerBottomGap,
    ) = f;
    return ChatSelectionBar(
      environment: SelectionEnvironment(
        conversationId: widget.conversationId,
        conversationTitle: title,
        currentUserId: currentUserId,
        canModerate: canDeleteAsModerator,
        senderName: (message) => message.isSentBy(currentUserId)
            ? tr('You')
            : senderFor(message, {
                for (final member
                    in groupDetail?.members ?? const <GroupMember>[])
                  member.profile.id: member,
              }).name,
        onChanged: _refreshThread,
      ),
      desktop: desktop,
      bottomGap: composerBottomGap,
    );
  }
}
