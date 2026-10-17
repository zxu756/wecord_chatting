import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/later/later_cards.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Which saved messages the page lists.
enum SavedFilter { active, done }

/// The user's saved messages ("Later"): jump to one, mark it done (and
/// undo that), or remove it. Entries whose message was deleted or can no
/// longer be read say "Message unavailable".
class SavedMessagesScreen extends ConsumerStatefulWidget {
  const SavedMessagesScreen({super.key});

  static const path = '/saved';

  @override
  ConsumerState<SavedMessagesScreen> createState() =>
      _SavedMessagesScreenState();
}

class _SavedMessagesScreenState extends ConsumerState<SavedMessagesScreen> {
  var _filter = SavedFilter.active;
  String? _busyId;
  String? _error;

  Future<void> _refresh() async {
    ref.invalidate(savedMessagesProvider);
    await ref.read(savedMessagesProvider.future);
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() {
      _busyId = id;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(savedMessagesProvider);
      await ref.read(savedMessagesProvider.future);
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr('Something went wrong. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _busyId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final saved = ref.watch(savedMessagesProvider);
    final conversations = {
      for (final conversation
          in ref.watch(conversationsProvider).value ??
              const <ConversationSummary>[])
        conversation.id: conversation,
    };
    final circles = {
      for (final circle
          in ref.watch(circleSummariesProvider).value ??
              const <CircleSummary>[])
        circle.id: circle,
    };
    final all = saved.value ?? const <SavedMessage>[];
    final active = all.where((message) => !message.isDone).toList();
    final done = all.where((message) => message.isDone).toList();
    final shown = _filter == SavedFilter.active ? active : done;

    Widget chip(SavedFilter filter, String label, int count) {
      return WeCordChip(
        key: ValueKey('saved-filter-${filter.name}'),
        label: label,
        count: count == 0 ? null : count,
        onPaper: true,
        selected: _filter == filter,
        onPressed: () => setState(() => _filter = filter),
      );
    }

    final Widget body = saved.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('Could not load saved messages.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.dangerText),
            ),
          ),
        ],
      ),
      data: (_) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  key: const ValueKey('saved-error'),
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ),
            ),
          if (shown.isEmpty)
            _EmptySaved(filter: _filter)
          else
            for (final (index, message) in shown.indexed) ...[
              if (index > 0) const SizedBox(height: 10),
              _SavedCard(
                message: message,
                conversation: conversations[message.conversationId],
                circles: circles,
                busy: _busyId == message.id,
                onJump: () => openMessage(
                  context,
                  ref,
                  conversationId: message.conversationId,
                  messageId: message.messageId,
                  conversation: conversations[message.conversationId],
                ),
                onToggleDone: () => unawaited(
                  _run(
                    message.id,
                    () => ref
                        .read(savedMessagesRepositoryProvider)
                        .setDone(message.id, done: !message.isDone),
                  ),
                ),
                onRemove: () => unawaited(
                  _run(
                    message.id,
                    () => ref
                        .read(savedMessagesRepositoryProvider)
                        .remove(message.id),
                  ),
                ),
              ),
            ],
        ],
      ),
    );

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(
                  title: tr('Saved'),
                  actions: [
                    WeCordIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: tr('Refresh'),
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: _refresh,
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      chip(SavedFilter.active, tr('Active'), active.length),
                      const SizedBox(width: 6),
                      chip(SavedFilter.done, tr('Done'), done.length),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(onRefresh: _refresh, child: body),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  const _SavedCard({
    required this.message,
    required this.conversation,
    required this.circles,
    required this.busy,
    required this.onJump,
    required this.onToggleDone,
    required this.onRemove,
  });

  final SavedMessage message;
  final ConversationSummary? conversation;
  final Map<String, CircleSummary> circles;
  final bool busy;
  final VoidCallback onJump;
  final VoidCallback onToggleDone;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final available = message.available;
    final place = conversationPlaceLabel(conversation, circles);
    final name = available && message.senderName.isNotEmpty
        ? message.senderName
        : tr('Message');
    final savedAt = describeWhen(
      MaterialLocalizations.of(context),
      message.savedAt.toLocal(),
      clock.now(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return LaterCard(
      key: ValueKey('saved-${message.id}'),
      onPressed: available ? onJump : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            name: name,
            avatarUrl: available ? message.senderAvatarUrl : null,
            badge: LaterAvatarBadge(
              color: message.isDone ? c.success : c.accent,
              icon: message.isDone
                  ? Icons.check_rounded
                  : Icons.bookmark_rounded,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                if (place != null && place.isNotEmpty)
                  Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                const SizedBox(height: 8),
                LaterMessagePreview(
                  available: available,
                  text: laterPreview(
                    conversationId: message.conversationId,
                    body: message.body,
                    type: message.type,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (available)
                            WeCordButton(
                              key: ValueKey('saved-jump-${message.id}'),
                              label: tr('Jump'),
                              size: WeCordButtonSize.small,
                              variant: WeCordButtonVariant.secondary,
                              onPressed: onJump,
                            ),
                          if (available || message.isDone)
                            WeCordButton(
                              key: ValueKey('saved-done-${message.id}'),
                              label: message.isDone
                                  ? tr('Undo')
                                  : tr('Mark done'),
                              icon: message.isDone
                                  ? Icons.undo_rounded
                                  : Icons.check_rounded,
                              size: WeCordButtonSize.small,
                              variant: message.isDone
                                  ? WeCordButtonVariant.ghost
                                  : WeCordButtonVariant.secondary,
                              loading: busy,
                              onPressed: busy ? null : onToggleDone,
                            ),
                        ],
                      ),
                    ),
                    WeCordIconButton(
                      key: ValueKey('saved-remove-${message.id}'),
                      icon: Icons.bookmark_remove_outlined,
                      tooltip: tr('Remove from Saved'),
                      variant: WeCordButtonVariant.ghost,
                      size: 36,
                      onPressed: busy ? null : onRemove,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    tr('Saved {time}', {'time': savedAt}),
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySaved extends StatelessWidget {
  const _EmptySaved({required this.filter});

  final SavedFilter filter;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final active = filter == SavedFilter.active;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      child: Column(
        children: [
          SettingsIconTile(
            icon: active
                ? Icons.bookmark_border_rounded
                : Icons.check_circle_outline_rounded,
            size: 56,
          ),
          const SizedBox(height: 14),
          Text(
            active ? tr('Nothing saved yet') : tr('Nothing done yet'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            active
                ? tr(
                    "Choose Save for later in a message's menu to keep it here.",
                  )
                : tr('Messages you mark done show up here.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
