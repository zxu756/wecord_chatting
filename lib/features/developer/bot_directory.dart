import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/developer/developer_repository.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The search is at least this long, so "a" does not list every bot.
const _minSearchLength = 2;

/// Opens the bot search. With [addToChatId] it adds the chosen bot to that
/// group instead of starting a direct chat.
void openFindBot(BuildContext context, {String? addToChatId}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => FindBotScreen(addToChatId: addToChatId),
    ),
  );
}

void openGroupBots(
  BuildContext context, {
  required String chatId,
  required bool isOwner,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => GroupBotsScreen(chatId: chatId, isOwner: isOwner),
    ),
  );
}

/// Friends → Find a bot: the way into the bot search.
class FindBotEntry extends StatelessWidget {
  const FindBotEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SettingsGroup(
        children: [
          SettingsRow(
            key: const ValueKey('find-bot-entry'),
            icon: Icons.smart_toy_outlined,
            tone: SettingsTone.accent,
            title: tr('Find a bot'),
            subtitle: tr('Chat with bots made by others'),
            onTap: () => openFindBot(context),
          ),
        ],
      ),
    );
  }
}

ImageProvider? _avatar(String? url) {
  if (url == null || url.isEmpty) {
    return null;
  }
  return NetworkImage(url);
}

/// Search for bots that are open to everyone, by name or username.
class FindBotScreen extends ConsumerStatefulWidget {
  const FindBotScreen({this.addToChatId, super.key});

  final String? addToChatId;

  @override
  ConsumerState<FindBotScreen> createState() => _FindBotScreenState();
}

class _FindBotScreenState extends ConsumerState<FindBotScreen> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<OpenBot> _results = const [];
  var _searched = false;
  var _loading = false;
  var _failed = false;
  String? _busyBot;

  /// Which search the results belong to, so a slow answer to an old search
  /// is ignored.
  var _searchId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    _debounce?.cancel();
    final text = _query.text.trim();
    final id = ++_searchId;
    if (text.length < _minSearchLength) {
      setState(() {
        _results = const [];
        _searched = false;
        _loading = false;
        _failed = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final found = await ref
          .read(developerRepositoryProvider)
          .searchBots(text);
      if (mounted && id == _searchId) {
        setState(() {
          _results = found;
          _searched = true;
          _loading = false;
        });
      }
    } on Object {
      if (mounted && id == _searchId) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  void _say(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _message(OpenBot bot) async {
    setState(() => _busyBot = bot.userId);
    try {
      final conversationId = await ref
          .read(chatsRepositoryProvider)
          .getOrCreateDirectConversation(bot.userId);
      ref.invalidate(conversationsProvider);
      if (!mounted) {
        return;
      }
      openPage(
        context,
        '${ChatsScreen.path}/$conversationId',
        extra: ChatThreadRouteExtra(
          title: bot.name,
          type: ConversationType.direct,
          avatarUrl: bot.avatarUrl,
        ),
      );
    } on Object {
      if (mounted) {
        _say(tr('Could not start the chat. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _busyBot = null);
      }
    }
  }

  Future<void> _add(OpenBot bot) async {
    final chatId = widget.addToChatId;
    if (chatId == null) {
      return;
    }
    setState(() => _busyBot = bot.userId);
    try {
      await ref
          .read(developerRepositoryProvider)
          .addBotToGroup(chatId, bot.userId);
      ref.invalidate(groupBotsProvider(chatId));
      if (mounted) {
        Navigator.of(context).maybePop();
      }
    } on Object {
      if (mounted) {
        _say(
          tr(
            'Could not add the bot. A group can have up to 5 bots, and '
            'some chats do not allow bots.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busyBot = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final adding = widget.addToChatId != null;
    return SettingsPage(
      title: adding ? tr('Add a bot') : tr('Find a bot'),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: WeCordTextField(
            fieldKey: const ValueKey('find-bot-field'),
            controller: _query,
            hint: tr('Search bots by name'),
            prefixIcon: Icons.search_rounded,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            onSubmitted: (_) => unawaited(_search()),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_failed)
          SettingsGroup(
            children: [
              SettingsRow(
                key: const ValueKey('find-bot-error'),
                icon: Icons.error_outline,
                tone: SettingsTone.danger,
                title: tr('Could not search. Try again.'),
                showChevron: false,
                onTap: () => unawaited(_search()),
              ),
            ],
          )
        else if (!_searched)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              tr(
                'Type at least 2 letters of a bot\'s name. Only bots whose '
                'makers opened them to everyone are listed.',
              ),
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
            ),
          )
        else if (_results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              tr('No bots found.'),
              key: const ValueKey('find-bot-empty'),
              style: TextStyle(fontSize: 13.5, color: c.muted),
            ),
          )
        else
          SettingsGroup(
            separatorIndent: 14,
            children: [
              for (final bot in _results)
                _BotResultRow(
                  bot: bot,
                  adding: adding,
                  busy: _busyBot == bot.userId,
                  onAction: _busyBot != null
                      ? null
                      : () => unawaited(adding ? _add(bot) : _message(bot)),
                ),
            ],
          ),
      ],
    );
  }
}

class _BotResultRow extends StatelessWidget {
  const _BotResultRow({
    required this.bot,
    required this.adding,
    required this.busy,
    required this.onAction,
  });

  final OpenBot bot;
  final bool adding;
  final bool busy;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final allowed = adding ? bot.allowGroups : bot.allowDirect;
    return Padding(
      key: ValueKey('find-bot-${bot.userId}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ThingAvatar(
            label: bot.name,
            size: 40,
            icon: Icons.smart_toy_outlined,
            image: _avatar(bot.avatarUrl),
            color: c.accentSoft,
            foregroundColor: c.accentText,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      bot.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    CircleTag(
                      label: tr('BOT'),
                      background: c.accent,
                      foreground: c.onAccent,
                    ),
                  ],
                ),
                if ((bot.description ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    bot.description!.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: c.muted,
                    ),
                  ),
                ],
                if (allowed) ...[
                  const SizedBox(height: 8),
                  WeCordButton(
                    key: ValueKey('find-bot-action-${bot.userId}'),
                    label: adding ? tr('Add') : tr('Message'),
                    size: WeCordButtonSize.small,
                    variant: WeCordButtonVariant.secondary,
                    loading: busy,
                    onPressed: onAction,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Group details: the entry for the bots in a group. Everyone in the group
/// sees which bots are there; the owner adds and removes them.
class GroupBotsRow extends ConsumerWidget {
  const GroupBotsRow({required this.chatId, required this.isOwner, super.key});

  final String chatId;
  final bool isOwner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots = ref.watch(groupBotsProvider(chatId)).value;
    // Nobody but the owner has a reason to open an empty list.
    if (bots == null || (bots.isEmpty && !isOwner)) {
      return const SizedBox.shrink();
    }
    return SettingsRow(
      key: const ValueKey('group-detail-bots'),
      icon: Icons.smart_toy_outlined,
      tone: SettingsTone.accent,
      title: tr('Bots'),
      subtitle: bots.isEmpty
          ? tr('Add a bot to this group')
          : bots.map((bot) => bot.name).join(', '),
      value: bots.isEmpty ? null : '${bots.length}',
      onTap: () => openGroupBots(context, chatId: chatId, isOwner: isOwner),
    );
  }
}

/// The bots in one group: who they are, and for the owner, add and remove.
class GroupBotsScreen extends ConsumerStatefulWidget {
  const GroupBotsScreen({
    required this.chatId,
    required this.isOwner,
    super.key,
  });

  final String chatId;
  final bool isOwner;

  @override
  ConsumerState<GroupBotsScreen> createState() => _GroupBotsScreenState();
}

class _GroupBotsScreenState extends ConsumerState<GroupBotsScreen> {
  String? _busyBot;

  Future<void> _remove(OpenBot bot) async {
    final confirmed = await showCircleDialog<bool>(
      context,
      builder: (context) => CircleDialog(
        title: tr('Remove bot'),
        message: tr('{name} leaves this group and sees nothing more of it.', {
          'name': bot.name,
        }),
        actions: [
          CircleDialogAction(
            label: tr('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CircleDialogAction.danger(
            key: const ValueKey('group-bot-remove-confirm'),
            label: tr('Remove'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busyBot = bot.userId);
    try {
      await ref
          .read(developerRepositoryProvider)
          .removeBotFromGroup(widget.chatId, bot.userId);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not remove the bot. Try again.'))),
        );
      }
    } finally {
      ref.invalidate(groupBotsProvider(widget.chatId));
      if (mounted) {
        setState(() => _busyBot = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final bots = ref.watch(groupBotsProvider(widget.chatId));
    return SettingsPage(
      title: tr('Bots in this group'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
          child: Text(
            tr(
              'A bot in a group reads the messages of this group and can '
              'write in it. Everyone in the group can see which bots are '
              'here.',
            ),
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
        ),
        bots.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.error_outline,
                tone: SettingsTone.danger,
                title: tr('Could not load the bots.'),
                subtitle: tr('Tap to try again.'),
                showChevron: false,
                onTap: () => ref.invalidate(groupBotsProvider(widget.chatId)),
              ),
            ],
          ),
          data: (list) => SettingsGroup(
            separatorIndent: 14,
            children: [
              for (final bot in list)
                Padding(
                  key: ValueKey('group-bot-${bot.userId}'),
                  padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                  child: Row(
                    children: [
                      ThingAvatar(
                        label: bot.name,
                        size: 36,
                        icon: Icons.smart_toy_outlined,
                        image: _avatar(bot.avatarUrl),
                        color: c.accentSoft,
                        foregroundColor: c.accentText,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          bot.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                      ),
                      if (widget.isOwner)
                        WeCordIconButton(
                          key: ValueKey('group-bot-remove-${bot.userId}'),
                          tooltip: tr('Remove bot'),
                          icon: Icons.person_remove_outlined,
                          variant: WeCordButtonVariant.ghost,
                          size: 36,
                          onPressed: _busyBot != null
                              ? null
                              : () => unawaited(_remove(bot)),
                        ),
                    ],
                  ),
                ),
              if (widget.isOwner)
                SettingsRow(
                  key: const ValueKey('group-bot-add'),
                  icon: Icons.add_rounded,
                  tone: SettingsTone.accent,
                  title: tr('Add a bot'),
                  showChevron: false,
                  onTap: () => openFindBot(context, addToChatId: widget.chatId),
                ),
              if (list.isEmpty && !widget.isOwner)
                SettingsRow(
                  title: tr('No bots in this group.'),
                  showChevron: false,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
