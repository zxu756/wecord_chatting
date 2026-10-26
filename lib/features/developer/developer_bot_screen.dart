import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_bot_repository.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/developer/bot_events_dialog.dart';
import 'package:wecord/features/developer/developer_repository.dart';
import 'package:wecord/features/developer/developer_screen.dart';
import 'package:wecord/features/interactions/bot_callback_dialog.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

void openDeveloperBot(BuildContext context, String botId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => DeveloperBotScreen(botId: botId),
    ),
  );
}

/// Settings → Developer → a bot: its token, where it gets events, who can
/// use it outside its circle, and what it did lately.
class DeveloperBotScreen extends ConsumerStatefulWidget {
  const DeveloperBotScreen({required this.botId, super.key});

  final String botId;

  @override
  ConsumerState<DeveloperBotScreen> createState() => _DeveloperBotScreenState();
}

class _DeveloperBotScreenState extends ConsumerState<DeveloperBotScreen> {
  var _busy = false;

  void _say(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs [action] with the page locked, then reloads the bots; says
  /// [failure] when it throws.
  Future<T?> _run<T>(
    Future<T> Function() action, {
    required String failure,
  }) async {
    setState(() => _busy = true);
    try {
      return await action();
    } on Object {
      if (mounted) {
        _say(failure);
      }
      return null;
    } finally {
      ref.invalidate(developerBotsProvider);
      ref.invalidate(botDeliveriesProvider(widget.botId));
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String label,
    bool danger = true,
  }) async {
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
          danger
              ? CircleDialogAction.danger(
                  key: const ValueKey('developer-confirm'),
                  label: label,
                  onPressed: () => Navigator.of(context).pop(true),
                )
              : CircleDialogAction.primary(
                  key: const ValueKey('developer-confirm'),
                  label: label,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _resetToken(DeveloperBot bot) async {
    if (!await _confirm(
      title: tr('Reset token'),
      message: tr(
        'The current token of {name} stops working right away. Programs '
        'using it need the new one.',
        {'name': bot.name},
      ),
      label: tr('Reset'),
      danger: false,
    )) {
      return;
    }
    final secret = await _run(
      () => ref.read(circleBotRepositoryProvider).regenerateToken(bot.id),
      failure: tr('Could not reset the token. Try again.'),
    );
    if (secret != null && mounted) {
      await showCircleDialog<void>(
        context,
        builder: (context) => _TokenDialog(token: secret.token),
      );
    }
  }

  Future<void> _revokeToken(DeveloperBot bot) async {
    if (!await _confirm(
      title: tr('Revoke token'),
      message: tr('{name} stops working until you reset its token.', {
        'name': bot.name,
      }),
      label: tr('Revoke'),
    )) {
      return;
    }
    await _run(
      () => ref.read(circleBotRepositoryProvider).revokeToken(bot.id),
      failure: tr('Could not revoke the token. Try again.'),
    );
  }

  Future<void> _testEvent(DeveloperBot bot) async {
    final done = await _run(() async {
      await ref.read(developerRepositoryProvider).sendTestEvent(bot.id);
      return true;
    }, failure: tr('Could not send the test event. Try again.'));
    if (done == true && mounted) {
      _say(tr('A test event is on its way.'));
    }
  }

  Future<void> _rotateEventSecret(DeveloperBot bot) async {
    if (!await _confirm(
      title: tr('Reset event secret'),
      message: tr(
        'Events signed with the old secret stop being accepted by your '
        'program once it uses the new one.',
      ),
      label: tr('Reset'),
      danger: false,
    )) {
      return;
    }
    final result = await _run(
      () => ref.read(developerRepositoryProvider).rotateSecret(bot.id),
      failure: tr('Could not reset the secret. Try again.'),
    );
    if (result?.secret != null && mounted) {
      await showBotEventSecret(context, result!.secret!, created: false);
    }
  }

  Future<void> _clearEvents(DeveloperBot bot) async {
    if (!await _confirm(
      title: tr('Remove event address'),
      message: tr(
        '{name} stops getting events. Events that are still waiting are '
        'dropped.',
        {'name': bot.name},
      ),
      label: tr('Remove'),
    )) {
      return;
    }
    await _run(
      () => ref.read(developerRepositoryProvider).clearSubscription(bot.id),
      failure: tr('Could not remove the event address. Try again.'),
    );
  }

  Future<void> _editDescription(DeveloperBot bot) async {
    final text = await showCircleDialog<String>(
      context,
      builder: (context) => _DescriptionDialog(initial: bot.description ?? ''),
    );
    if (text == null || !mounted) {
      return;
    }
    await _setAvailability(bot, description: text);
  }

  Future<void> _setAvailability(
    DeveloperBot bot, {
    String? description,
    bool? direct,
    bool? groups,
  }) async {
    await _run(
      () => ref
          .read(developerRepositoryProvider)
          .setAvailability(
            bot.id,
            description: description ?? bot.description ?? '',
            direct: direct ?? bot.allowDirect,
            groups: groups ?? bot.allowGroups,
          ),
      failure: tr('Could not save. Try again.'),
    );
  }

  Future<void> _copy(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      _say(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final bots = ref.watch(developerBotsProvider);
    final bot = bots.value
        ?.where((candidate) => candidate.id == widget.botId)
        .firstOrNull;
    if (bot == null) {
      return SettingsPage(
        title: tr('Bot'),
        children: [
          if (bots.isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SettingsGroup(
              children: [
                SettingsRow(
                  key: const ValueKey('developer-bot-missing'),
                  icon: Icons.error_outline,
                  tone: SettingsTone.danger,
                  title: tr('This bot is not available.'),
                  subtitle: tr('Tap to try again.'),
                  showChevron: false,
                  onTap: () => ref.invalidate(developerBotsProvider),
                ),
              ],
            ),
        ],
      );
    }
    final apiUrl = ref
        .watch(appConfigProvider)
        ?.supabaseUrl
        .resolve('functions/v1/bot-api')
        .toString();
    return SettingsPage(
      title: bot.name,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Text(
            [
              bot.circleName,
              if (bot.bot.username.isNotEmpty) '@${bot.bot.username}',
            ].where((part) => part.isNotEmpty).join(' · '),
            style: TextStyle(fontSize: 13.5, color: c.muted),
          ),
        ),
        SettingsSectionHeader(tr('Token')),
        SettingsGroup(
          children: [
            if (apiUrl != null)
              SettingsRow(
                key: const ValueKey('developer-api-address'),
                icon: Icons.link_rounded,
                title: tr('API address'),
                subtitle: apiUrl,
                showChevron: false,
                trailing: Icon(Icons.copy_rounded, size: 18, color: c.subtle),
                onTap: () =>
                    unawaited(_copy(apiUrl, tr('API address copied.'))),
              ),
            SettingsRow(
              key: const ValueKey('developer-reset-token'),
              icon: Icons.key_outlined,
              title: tr('Reset token'),
              subtitle: bot.bot.hasToken
                  ? tr('Make a new token; the current one stops working')
                  : tr('Token revoked. Make a new one to use the bot.'),
              onTap: _busy ? null : () => unawaited(_resetToken(bot)),
            ),
            if (bot.bot.hasToken)
              SettingsRow(
                key: const ValueKey('developer-revoke-token'),
                icon: Icons.key_off_outlined,
                title: tr('Revoke token'),
                destructive: true,
                showChevron: false,
                onTap: _busy ? null : () => unawaited(_revokeToken(bot)),
              ),
          ],
        ),
        SettingsSectionHeader(tr('Events')),
        SettingsGroup(
          footer: _eventsFooter(bot.events),
          children: [
            SettingsRow(
              key: const ValueKey('developer-event-address'),
              icon: Icons.bolt_rounded,
              title: tr('Event address'),
              subtitle: bot.events.isSet
                  ? '${bot.events.url}\n${developerEventsStatus(bot.events)}'
                  : tr('Not set. The bot can still ask for things by polling.'),
              onTap: _busy
                  ? null
                  : () => unawaited(showBotEventsDialog(context, ref, bot)),
            ),
            if (bot.events.isSet && bot.events.enabled)
              SettingsRow(
                key: const ValueKey('developer-test-event'),
                icon: Icons.send_rounded,
                title: tr('Send a test event'),
                showChevron: false,
                onTap: _busy ? null : () => unawaited(_testEvent(bot)),
              ),
            if (bot.events.isSet)
              SettingsRow(
                key: const ValueKey('developer-rotate-event-secret'),
                icon: Icons.vpn_key_outlined,
                title: tr('Reset event secret'),
                onTap: _busy ? null : () => unawaited(_rotateEventSecret(bot)),
              ),
            if (bot.events.isSet)
              SettingsRow(
                key: const ValueKey('developer-clear-events'),
                icon: Icons.link_off_rounded,
                title: tr('Remove event address'),
                destructive: true,
                showChevron: false,
                onTap: _busy ? null : () => unawaited(_clearEvents(bot)),
              ),
            SettingsRow(
              key: const ValueKey('developer-callback'),
              icon: Icons.webhook_outlined,
              title: tr('Callback address'),
              subtitle: tr('Where button presses and slash commands go'),
              onTap: _busy
                  ? null
                  : () => unawaited(
                      showBotCallbackDialog(
                        context,
                        ref,
                        bot.bot,
                      ).then((_) => ref.invalidate(developerBotsProvider)),
                    ),
            ),
          ],
        ),
        if (bot.events.isSet) _DeliveriesSection(botId: bot.id),
        SettingsSectionHeader(tr('Availability')),
        SettingsGroup(
          footer: tr(
            'Open bots can be found by anyone who searches for them. They '
            'only see the chats they are in.',
          ),
          children: [
            SettingsRow(
              key: const ValueKey('developer-description'),
              icon: Icons.notes_rounded,
              title: tr('Description'),
              subtitle: (bot.description ?? '').trim().isEmpty
                  ? tr('Not set')
                  : bot.description,
              onTap: _busy ? null : () => unawaited(_editDescription(bot)),
            ),
            SettingsRow.toggle(
              key: const ValueKey('developer-allow-direct'),
              icon: Icons.chat_bubble_outline_rounded,
              title: tr('People can message this bot'),
              subtitle: tr('Anyone can start a direct chat with it'),
              value: bot.allowDirect,
              onChanged: _busy
                  ? null
                  : (on) => unawaited(_setAvailability(bot, direct: on)),
            ),
            SettingsRow.toggle(
              key: const ValueKey('developer-allow-groups'),
              icon: Icons.groups_outlined,
              title: tr('Group owners can add this bot'),
              subtitle: tr('A group owner can bring it into a group chat'),
              value: bot.allowGroups,
              onChanged: _busy
                  ? null
                  : (on) => unawaited(_setAvailability(bot, groups: on)),
            ),
          ],
        ),
        _CallsSection(botId: bot.id),
      ],
    );
  }

  String? _eventsFooter(BotEventSubscription events) {
    if (!events.isSet) {
      return tr(
        'Events tell your program what happens in the bot\'s chats without '
        'polling. They are signed, so your program can check they come '
        'from WeCord.',
      );
    }
    if (!events.enabled) {
      return tr(
        'Paused: too many events failed in a row, or the person who set '
        'this up no longer manages the circle. Save the address again to '
        'turn it back on.',
      );
    }
    if (events.droppedCount > 0) {
      return tr('{count} events were skipped because the bot was too busy.', {
        'count': events.droppedCount,
      });
    }
    return null;
  }
}

class _DeliveriesSection extends ConsumerWidget {
  const _DeliveriesSection({required this.botId});

  final String botId;

  static String stateLabel(BotEventDelivery delivery) {
    return switch (delivery.state) {
      'delivered' => tr('Delivered'),
      'failed' => tr('Failed'),
      'dropped' => tr('Skipped'),
      'sending' => tr('Sending'),
      _ => tr('Waiting'),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final deliveries = ref.watch(botDeliveriesProvider(botId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSectionHeader(
          tr('Recent events'),
          trailing: WeCordIconButton(
            key: const ValueKey('developer-refresh-deliveries'),
            tooltip: tr('Refresh'),
            icon: Icons.refresh_rounded,
            variant: WeCordButtonVariant.ghost,
            size: 32,
            onPressed: () => ref.invalidate(botDeliveriesProvider(botId)),
          ),
        ),
        deliveries.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.error_outline,
                tone: SettingsTone.danger,
                title: tr('Could not load the events.'),
                subtitle: tr('Tap to try again.'),
                showChevron: false,
                onTap: () => ref.invalidate(botDeliveriesProvider(botId)),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                  child: Text(
                    tr('Nothing has been sent yet.'),
                    key: const ValueKey('developer-no-deliveries'),
                    style: TextStyle(fontSize: 13.5, color: c.muted),
                  ),
                )
              : SettingsGroup(
                  children: [
                    for (final delivery in list.take(10))
                      SettingsRow(
                        key: ValueKey('developer-delivery-${delivery.id}'),
                        icon: delivery.isDelivered
                            ? Icons.check_circle_outline_rounded
                            : delivery.isWaiting
                            ? Icons.schedule_rounded
                            : Icons.error_outline_rounded,
                        tone: delivery.isDelivered
                            ? SettingsTone.success
                            : delivery.isWaiting
                            ? SettingsTone.neutral
                            : SettingsTone.danger,
                        title: delivery.event,
                        subtitle: [
                          stateLabel(delivery),
                          if (delivery.status != null && !delivery.isDelivered)
                            'HTTP ${delivery.status}',
                          developerTimeAgo(delivery.createdAt),
                        ].join(' · '),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _CallsSection extends ConsumerWidget {
  const _CallsSection({required this.botId});

  final String botId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final calls = ref.watch(botApiCallsProvider(botId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSectionHeader(
          tr('Recent API calls'),
          trailing: WeCordIconButton(
            key: const ValueKey('developer-refresh-calls'),
            tooltip: tr('Refresh'),
            icon: Icons.refresh_rounded,
            variant: WeCordButtonVariant.ghost,
            size: 32,
            onPressed: () => ref.invalidate(botApiCallsProvider(botId)),
          ),
        ),
        calls.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stack) => SettingsGroup(
            children: [
              SettingsRow(
                icon: Icons.error_outline,
                tone: SettingsTone.danger,
                title: tr('Could not load the calls.'),
                subtitle: tr('Tap to try again.'),
                showChevron: false,
                onTap: () => ref.invalidate(botApiCallsProvider(botId)),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                  child: Text(
                    tr('This bot has not called the API yet.'),
                    key: const ValueKey('developer-no-calls'),
                    style: TextStyle(fontSize: 13.5, color: c.muted),
                  ),
                )
              : SettingsGroup(
                  children: [
                    for (var i = 0; i < list.take(10).length; i++)
                      SettingsRow(
                        key: ValueKey('developer-call-$i'),
                        icon: list[i].succeeded
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        tone: list[i].succeeded
                            ? SettingsTone.success
                            : SettingsTone.danger,
                        title: '${list[i].method} ${list[i].route}',
                        subtitle: developerTimeAgo(list[i].at),
                        value: '${list[i].status}',
                        showChevron: false,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TokenDialog extends StatelessWidget {
  const _TokenDialog({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CircleDialog(
      title: tr('New bot token'),
      message: tr(
        'Copy the token now: it is shown only once. Anyone with it can '
        'act as this bot.',
      ),
      content: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(WeCordRadii.md),
        ),
        child: SelectableText(
          token,
          key: const ValueKey('developer-token'),
          style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: c.ink),
        ),
      ),
      actions: [
        CircleDialogAction(
          key: const ValueKey('developer-token-copy'),
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

class _DescriptionDialog extends StatefulWidget {
  const _DescriptionDialog({required this.initial});

  final String initial;

  @override
  State<_DescriptionDialog> createState() => _DescriptionDialogState();
}

class _DescriptionDialogState extends State<_DescriptionDialog> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Bot description'),
      message: tr('What the bot does. People see it when they find the bot.'),
      content: WeCordTextField(
        fieldKey: const ValueKey('developer-description-field'),
        controller: _text,
        autofocus: true,
        maxLength: 300,
        maxLines: 4,
        label: tr('Description'),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('developer-description-save'),
          label: tr('Save'),
          onPressed: () => Navigator.of(context).pop(_text.text.trim()),
        ),
      ],
    );
  }
}
