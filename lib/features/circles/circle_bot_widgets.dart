import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_bot_repository.dart';
import 'package:wecord/features/circles/circle_settings_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/circle_role.dart';
import 'package:wecord/shared/models/message_origin.dart';
import 'package:wecord/shared/ui/ui.dart';

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
    final result = await showCircleDialog<(String, CircleRole?)>(
      context,
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
    final confirmed = await showCircleDialog<bool>(
      context,
      builder: (context) => CircleDialog(
        title: title,
        message: message,
        actions: [
          CircleDialogAction(
            label: tr('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          action == _BotAction.regenerate
              ? CircleDialogAction.primary(
                  key: const ValueKey('bot-action-confirm'),
                  label: label,
                  onPressed: () => Navigator.of(context).pop(true),
                )
              : CircleDialogAction.danger(
                  key: const ValueKey('bot-action-confirm'),
                  label: label,
                  onPressed: () => Navigator.of(context).pop(true),
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
    return showCircleDialog<void>(
      context,
      builder: (context) => _BotTokenDialog(
        title: created ? tr('Bot created') : tr('New bot token'),
        token: secret.token,
        apiUrl: supabaseUrl?.resolve('functions/v1/bot-api').toString(),
      ),
    );
  }

  Future<void> _openMenu(CircleBot bot, Offset? position) async {
    final action = await showCircleActionMenu<_BotAction>(
      context,
      title: bot.name,
      position: position,
      items: [
        CircleMenuItem(
          value: _BotAction.regenerate,
          icon: Icons.key_outlined,
          label: tr('Reset token'),
        ),
        if (bot.hasToken)
          CircleMenuItem(
            value: _BotAction.revoke,
            icon: Icons.key_off_outlined,
            label: tr('Revoke token'),
            destructive: true,
          ),
        CircleMenuItem(
          value: _BotAction.delete,
          icon: Icons.delete_outline,
          label: tr('Delete bot'),
          destructive: true,
        ),
      ],
    );
    if (action != null && mounted) {
      await _act(bot, action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final bots = ref.watch(circleBotsProvider(_circleId));
    final list = bots.value ?? const <CircleBot>[];
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
        SettingsGroup(
          children: [
            if (bots.hasError)
              SettingsRow(
                icon: Icons.error_outline,
                title: tr('Could not load the bots.'),
              ),
            for (final bot in list)
              Padding(
                key: ValueKey('circle-bot-${bot.id}'),
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                child: Row(
                  children: [
                    ThingAvatar(
                      label: bot.name,
                      size: 36,
                      icon: Icons.smart_toy_outlined,
                      color: c.accentSoft,
                      foregroundColor: c.accentText,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
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
                              const SizedBox(width: 6),
                              CircleTag(
                                label: tr('BOT'),
                                background: c.accent,
                                foreground: c.onAccent,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (!bot.isMember)
                                tr('Removed from the circle')
                              else if (!bot.hasToken)
                                tr('Token revoked'),
                              if (bot.roleNames.isNotEmpty)
                                bot.roleNames.join(', '),
                              tr('{count} commands', {
                                'count': bot.commandCount,
                              }),
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    Builder(
                      builder: (buttonContext) => WeCordIconButton(
                        key: ValueKey('circle-bot-menu-${bot.id}'),
                        tooltip: tr('Bot actions'),
                        icon: Icons.more_horiz_rounded,
                        variant: WeCordButtonVariant.ghost,
                        size: 36,
                        onPressed: _busy
                            ? null
                            : () {
                                final box =
                                    buttonContext.findRenderObject()
                                        as RenderBox?;
                                unawaited(
                                  _openMenu(
                                    bot,
                                    box?.localToGlobal(
                                      box.size.bottomRight(Offset.zero),
                                    ),
                                  ),
                                );
                              },
                      ),
                    ),
                  ],
                ),
              ),
            SettingsRow(
              key: const ValueKey('bot-create-button'),
              icon: Icons.add_rounded,
              tone: SettingsTone.accent,
              title: tr('New bot'),
              showChevron: false,
              onTap: _busy || bots.isLoading ? null : _create,
            ),
          ],
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
    final c = context.tokens.colors;
    const radius = BorderRadius.all(Radius.circular(WeCordRadii.lg));
    const idle = WeCordFieldBorder(
      borderRadius: radius,
      borderSide: BorderSide.none,
    );
    return CircleDialog(
      title: tr('New bot'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('bot-name-field'),
            controller: _name,
            autofocus: true,
            maxLength: CircleBot.maxNameLength,
            label: tr('Bot name'),
            errorText: _error,
            onSubmitted: (_) => _submit(),
          ),
          if (widget.roles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                tr('Role'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ),
            DropdownButtonFormField<CircleRole?>(
              key: const ValueKey('bot-role-field'),
              initialValue: _role,
              isExpanded: true,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
              dropdownColor: c.panel,
              icon: Icon(Icons.expand_more_rounded, color: c.muted),
              decoration: InputDecoration(
                filled: true,
                fillColor: c.raised,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: idle,
                enabledBorder: idle,
                focusedBorder: WeCordFieldBorder(
                  borderRadius: radius,
                  borderSide: BorderSide(color: c.accent, width: 1.5),
                ),
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
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('bot-create-submit'),
          label: tr('Create'),
          onPressed: _submit,
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
    final c = context.tokens.colors;
    return CircleDialog(
      title: title,
      message: tr(
        'Copy the token now: it is shown only once. Anyone with it can '
        'act as this bot.',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            child: SelectableText(
              token,
              key: const ValueKey('bot-token'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: c.ink,
              ),
            ),
          ),
          if (apiUrl case final url?) ...[
            const SizedBox(height: 12),
            Text(
              tr('API address'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(url, style: TextStyle(fontSize: 12.5, color: c.ink)),
          ],
        ],
      ),
      actions: [
        CircleDialogAction(
          key: const ValueKey('bot-token-copy'),
          label: tr('Copy'),
          onPressed: () {
            unawaited(Clipboard.setData(ClipboardData(text: token)));
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(tr('Token copied.'))));
          },
        ),
        CircleDialogAction.primary(
          label: tr('Done'),
          onPressed: () => Navigator.of(context).pop(),
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
