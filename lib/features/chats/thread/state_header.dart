part of '../chat_thread_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Header and More menu.
extension _ThreadHeaderState on _ChatThreadScreenState {
  void _toggleMessageSearch() {
    setState(() {
      _isSearchingMessages = !_isSearchingMessages;
      if (!_isSearchingMessages) {
        _searchController.clear();
        _messageSearchQuery = '';
      }
    });
  }

  /// "16 members · 4 online" under the title of a group or of a channel
  /// without a topic; null for direct chats and threads (and while the
  /// members load), which show the person's presence instead.
  String? _memberLine({
    required ConversationType? type,
    required GroupDetail? groupDetail,
    required ConversationSummary? summary,
    required Set<String> onlineUserIds,
  }) {
    final Set<String>? ids = switch (type) {
      ConversationType.group =>
        groupDetail == null
            ? null
            : {for (final member in groupDetail.members) member.profile.id},
      ConversationType.channel => widget.circleMemberIds,
      _ => null,
    };
    final count =
        ids?.length ??
        (type == ConversationType.group && (summary?.memberCount ?? 0) > 0
            ? summary!.memberCount
            : null);
    if (count == null) {
      return null;
    }
    final online = ids == null ? 0 : ids.where(onlineUserIds.contains).length;
    return [
      count == 1 ? tr('1 member') : tr('{count} members', {'count': count}),
      if (online > 0) tr('{count} online', {'count': online}),
    ].join(' · ');
  }

  void _showTopic(String title, String topic) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: SelectableText(topic),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Close')),
          ),
        ],
      ),
    );
  }

  void _showGroupDetails(String title) {
    showWeCordSheet<void>(
      context,
      detents: GroupDetailSheet.detents,
      initialDetent: GroupDetailSheet.initialDetent,
      builder: (context, scrollController) {
        return GroupDetailSheet(
          conversationId: widget.conversationId,
          title: title,
          scrollController: scrollController,
        );
      },
    );
  }

  /// Opens the notes and lists panel on what [request] asks for.
  void _showWorkspace(WorkspaceRequest request) {
    ref.read(workspaceRequestProvider.notifier).state = null;
    final alreadyOpen = _workspaceOpen;
    setState(() {
      _workspaceOpen = true;
      _workspaceRequest = request;
    });
    unawaited(
      ref
          .read(panelLayoutProvider.notifier)
          .setCollapsed(ResizablePanel.docs, false),
    );
    if (alreadyOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _workspaceKey.currentState?.show(request);
      });
    }
  }

  Future<void> _setThreadArchived(String threadId, bool archived) async {
    try {
      await ref
          .read(chatsRepositoryProvider)
          .setThreadArchived(threadId: threadId, archived: archived);
      ref.invalidate(chatConversationSummaryProvider(widget.conversationId));
      ref.invalidate(conversationsProvider);
      _showSnackBar(
        archived ? tr('Thread archived.') : tr('Thread unarchived.'),
      );
    } catch (_) {
      _showSnackBar(
        archived
            ? tr('Could not archive thread. Try again.')
            : tr('Could not unarchive thread. Try again.'),
      );
    }
  }

  /// Message search for this conversation (and its circle, and
  /// everywhere), starting with what is in the search field.
  void _openFullSearch() {
    final summary = ref
        .read(chatConversationSummaryProvider(widget.conversationId))
        .value;
    var title = (widget.title ?? summary?.title)?.trim();
    if (title != null && title.startsWith('# ')) {
      title = title.substring(2);
    }
    openPage(
      context,
      GlobalMessageSearchScreen.location(
        conversationId: widget.conversationId,
        conversationTitle: title == null || title.isEmpty ? null : title,
        conversationType: widget.conversationType ?? summary?.type,
        circleId: summary?.circleId ?? _circleId,
        query: _searchController.text,
      ),
    );
  }
}
