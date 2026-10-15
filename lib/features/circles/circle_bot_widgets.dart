import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_bot_repository.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/message_origin.dart';

enum _BotAction { regenerate, revoke, delete }

/// Circle settings → Bots: bot accounts that programs drive through the
/// bot API with a token.
class CircleBotsSection extends ConsumerStatefulWidget {
  const CircleBotsSection({required this.detail, super.key});

  final CircleDetail detail;

  @override
  ConsumerState<CircleBotsSection> createState() => _CircleBotsSectionState();
}

class _CircleBotsSectionState extends ConsumerState<CircleBotsSection> {
  var _busy = false;

  String get _circleId => widget.detail.circle.id;

  Future<T?> _run<T>(
    Future<T> Function(CircleBotRepository repository) action, {
    required String failure,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      return await action(ref.read(circleBotRepositoryProvider));
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
      return null;
    } finally {
      ref.invalidate(circleBotsProvider(_circleId));
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create() async {
    final result = await showDialog<(String, CircleRole?)>(
      context: context,
      builder: (context) => _NewBotDialog(roles: widget.detail.assignableRoles),
    );
    if (result == null || !mounted) {
      return;
    }
    final secret = await _run(
      (repository) => repository.createBot(
        circleId: _circleId,
        name: result.$1,
        roleId: result.$2?.id,
      ),
      failure: tr('Could not create the bot. Try again.'),
    );
    if (secret != null && mounted) {
      await _showToken(secret, created: true);
    }
  }

  Future<void> _act(CircleBot bot, _BotAction action) async {
    final (title, message, label) = switch (action) {
      _BotAction.regenerate => (
        tr('Reset token'),
        tr(
          'The current token of {name} stops working right away. Programs '
          'using it need the new one.',
          {'name': bot.name},
        ),
        tr('Reset'),
      ),
      _BotAction.revoke => (
        tr('Revoke token'),
        tr('{name} stops working until you reset its token.', {
          'name': bot.name,
        }),
        tr('Revoke'),
      ),
      _BotAction.delete => (
        tr('Delete bot'),
        tr(
          'Remove {name} from this circle and delete its token? Its '
          'messages stay.',
          {'name': bot.name},
        ),
        tr('Delete'),
      ),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('bot-action-confirm'),
            style: action == _BotAction.regenerate
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(label),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    switch (action) {
      case _BotAction.regenerate:
        final secret = await _run(
          (repository) => repository.regenerateToken(bot.id),
          failure: tr('Could not reset the token. Try again.'),
        );
        if (secret != null && mounted) {
          await _showToken(secret, created: false);
        }
      case _BotAction.revoke:
        await _run(
          (repository) => repository.revokeToken(bot.id),
          failure: tr('Could not revoke the token. Try again.'),
        );
      case _BotAction.delete:
        await _run(
          (repository) => repository.deleteBot(bot.id),
          failure: tr('Could not delete the bot. Try again.'),
        );
    }
  }

  Future<void> _showToken(CircleBotSecret secret, {required bool created}) {
    final supabaseUrl = ref.read(appConfigProvider)?.supabaseUrl;
    return showDialog<void>(
      context: context,
      builder: (context) => _BotTokenDialog(
        title: created ? tr('Bot created') : tr('New bot token'),
        token: secret.token,
        apiUrl: supabaseUrl?.resolve('functions/v1/bot-api').toString(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bots = ref.watch(circleBotsProvider(_circleId));
    final list = bots.valueOrNull ?? const <CircleBot>[];
    return Column(
      key: const ValueKey('circle-bots-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CircleSettingsHeader(
          tr('Bots'),
          subtitle: tr(
            'Bots are members that programs control through the bot API '
            'with a secret token. They follow the permissions of their '
            'roles.',
          ),
        ),
        if (bots.hasError)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(tr('Could not load the bots.')),
          ),
        for (final bot in list)
          ListTile(
            key: ValueKey('circle-bot-${bot.id}'),
            leading: const CircleAvatar(child: Icon(Icons.smart_toy_outlined)),
            title: Text(bot.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                if (!bot.isMember)
                  tr('Removed from the circle')
                else if (!bot.hasToken)
                  tr('Token revoked'),
                if (bot.roleNames.isNotEmpty) bot.roleNames.join(', '),
                tr('{count} commands', {'count': bot.commandCount}),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: PopupMenuButton<_BotAction>(
              key: ValueKey('circle-bot-menu-${bot.id}'),
              tooltip: tr('Bot actions'),
              enabled: !_busy,
              onSelected: (action) => unawaited(_act(bot, action)),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _BotAction.regenerate,
                  child: Text(tr('Reset token')),
                ),
                if (bot.hasToken)
                  PopupMenuItem(
                    value: _BotAction.revoke,
                    child: Text(tr('Revoke token')),
                  ),
                PopupMenuItem(
                  value: _BotAction.delete,
                  child: Text(
                    tr('Delete bot'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonalIcon(
              key: const ValueKey('bot-create-button'),
              onPressed: _busy || bots.isLoading ? null : _create,
              icon: const Icon(Icons.add),
              label: Text(tr('New bot')),
            ),
          ),
        ),
      ],
    );
  }
}

class _NewBotDialog extends StatefulWidget {
  const _NewBotDialog({required this.roles});

  /// Roles the current user may give.
  final List<CircleRole> roles;

  @override
  State<_NewBotDialog> createState() => _NewBotDialogState();
}

class _NewBotDialogState extends State<_NewBotDialog> {
  final _name = TextEditingController();
  CircleRole? _role;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = tr('Bot name is required.'));
      return;
    }
    Navigator.of(context).pop((name, _role));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('New bot')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('bot-name-field'),
            controller: _name,
            autofocus: true,
            maxLength: CircleBot.maxNameLength,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: tr('Bot name'),
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.roles.isNotEmpty) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<CircleRole?>(
              key: const ValueKey('bot-role-field'),
              initialValue: _role,
              isExpanded: true,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: tr('Role'),
              ),
              items: [
                DropdownMenuItem(child: Text(tr('No role'))),
                for (final role in widget.roles)
                  DropdownMenuItem(
                    value: role,
                    child: Text(
                      role.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (role) => setState(() => _role = role),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('bot-create-submit'),
          onPressed: _submit,
          child: Text(tr('Create')),
        ),
      ],
    );
  }
}

class _BotTokenDialog extends StatelessWidget {
  const _BotTokenDialog({
    required this.title,
    required this.token,
    this.apiUrl,
  });

  final String title;
  final String token;
  final String? apiUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Copy the token now: it is shown only once. Anyone with it can '
              'act as this bot.',
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            token,
            key: const ValueKey('bot-token'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
          if (apiUrl case final url?) ...[
            const SizedBox(height: 12),
            Text(tr('API address'), style: theme.textTheme.labelMedium),
            SelectableText(url, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        TextButton.icon(
          key: const ValueKey('bot-token-copy'),
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: token)));
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(tr('Token copied.'))));
          },
          icon: const Icon(Icons.copy_outlined),
          label: Text(tr('Copy')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Done')),
        ),
      ],
    );
  }
}

/// Above a bot's answer to a slash command: who used which command.
class InteractionOrigin extends StatelessWidget {
  const InteractionOrigin({
    required this.interaction,
    required this.foregroundColor,
    super.key,
  });

  final MessageInteraction interaction;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    final muted = foregroundColor.withValues(alpha: 0.75);
    return Padding(
      key: const ValueKey('message-interaction'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.subdirectory_arrow_right, size: 14, color: muted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              tr('{name} used /{command}', {
                'name': interaction.userName,
                'command': interaction.command,
              }),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
