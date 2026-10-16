import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/channel_webhook.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A channel's webhooks, for members who can manage them.
final channelWebhooksProvider = FutureProvider.autoDispose
    .family<List<ChannelWebhook>, String>((ref, channelId) {
      return ref
          .watch(circlesRepositoryProvider)
          .listChannelWebhooks(channelId);
    });

/// Channel settings → Integrations: the channel's webhooks, with creating,
/// renaming, regenerating the URL and deleting.
class ChannelWebhooksSection extends ConsumerStatefulWidget {
  const ChannelWebhooksSection({required this.channel, super.key});

  final CircleChannel channel;

  @override
  ConsumerState<ChannelWebhooksSection> createState() =>
      _ChannelWebhooksSectionState();
}

enum _WebhookAction { rename, regenerate, delete }

class _ChannelWebhooksSectionState
    extends ConsumerState<ChannelWebhooksSection> {
  var _busy = false;

  Future<T?> _run<T>(
    Future<T> Function(CirclesRepository repository) action, {
    required String failure,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final result = await action(ref.read(circlesRepositoryProvider));
      ref.invalidate(channelWebhooksProvider(widget.channel.id));
      return result;
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(failure)));
      return null;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create() async {
    final name = await showCircleDialog<String>(
      context,
      builder: (context) => _WebhookNameDialog(
        title: tr('New webhook'),
        action: tr('Create'),
        initialName: 'Webhook',
      ),
    );
    if (name == null || !mounted) {
      return;
    }
    final secret = await _run(
      (repository) => repository.createChannelWebhook(
        channelId: widget.channel.id,
        name: name,
      ),
      failure: tr('Could not create the webhook. Try again.'),
    );
    if (secret != null && mounted) {
      await _showUrl(secret, created: true);
    }
  }

  Future<void> _rename(ChannelWebhook webhook) async {
    final name = await showCircleDialog<String>(
      context,
      builder: (context) => _WebhookNameDialog(
        title: tr('Rename webhook'),
        action: tr('Save'),
        initialName: webhook.name,
      ),
    );
    if (name == null || name == webhook.name || !mounted) {
      return;
    }
    await _run(
      (repository) =>
          repository.renameChannelWebhook(webhookId: webhook.id, name: name),
      failure: tr('Could not rename the webhook. Try again.'),
    );
  }

  Future<void> _regenerate(ChannelWebhook webhook) async {
    final confirmed = await _confirm(
      title: tr('Regenerate URL'),
      message: tr(
        'The current URL of "{name}" stops working right away. '
        'Services using it need the new one.',
        {'name': webhook.name},
      ),
      action: tr('Regenerate'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    final secret = await _run(
      (repository) => repository.regenerateWebhookToken(webhook.id),
      failure: tr('Could not regenerate the URL. Try again.'),
    );
    if (secret != null && mounted) {
      await _showUrl(secret, created: false);
    }
  }

  Future<void> _delete(ChannelWebhook webhook) async {
    final confirmed = await _confirm(
      title: tr('Delete webhook'),
      message: tr(
        'Delete "{name}"? Its URL stops working. Messages it '
        'posted stay.',
        {'name': webhook.name},
      ),
      action: tr('Delete'),
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.deleteChannelWebhook(webhook.id),
      failure: tr('Could not delete the webhook. Try again.'),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
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
          destructive
              ? CircleDialogAction.danger(
                  key: const ValueKey('webhook-confirm'),
                  label: action,
                  onPressed: () => Navigator.of(context).pop(true),
                )
              : CircleDialogAction.primary(
                  key: const ValueKey('webhook-confirm'),
                  label: action,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _showUrl(ChannelWebhookSecret secret, {required bool created}) {
    final supabaseUrl = ref.read(appConfigProvider)?.supabaseUrl;
    return showCircleDialog<void>(
      context,
      builder: (context) => _WebhookUrlDialog(
        title: created ? tr('Webhook created') : tr('New webhook URL'),
        url: supabaseUrl == null ? null : secret.urlFor(supabaseUrl),
      ),
    );
  }

  Future<void> _openMenu(ChannelWebhook webhook, Offset? position) async {
    final action = await showCircleActionMenu<_WebhookAction>(
      context,
      title: webhook.name,
      position: position,
      items: [
        CircleMenuItem(
          value: _WebhookAction.rename,
          icon: Icons.edit_outlined,
          label: tr('Rename'),
        ),
        CircleMenuItem(
          value: _WebhookAction.regenerate,
          icon: Icons.autorenew_rounded,
          label: tr('Regenerate URL'),
        ),
        CircleMenuItem(
          value: _WebhookAction.delete,
          icon: Icons.delete_outline,
          label: tr('Delete'),
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) {
      return;
    }
    unawaited(switch (action) {
      _WebhookAction.rename => _rename(webhook),
      _WebhookAction.regenerate => _regenerate(webhook),
      _WebhookAction.delete => _delete(webhook),
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final webhooks = ref.watch(channelWebhooksProvider(widget.channel.id));
    final list = webhooks.valueOrNull;
    return Column(
      key: const ValueKey('channel-integrations'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(tr('Integrations')),
        SettingsGroup(
          children: [
            ...webhooks.when(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, stackTrace) => [
                _WebhookNote(tr('Could not load webhooks.')),
              ],
              data: (webhooks) => [
                if (webhooks.isEmpty) _WebhookNote(tr('No webhooks yet.')),
                for (final webhook in webhooks)
                  _WebhookRow(
                    key: ValueKey('webhook-${webhook.id}'),
                    webhook: webhook,
                    busy: _busy,
                    onMenu: (position) => _openMenu(webhook, position),
                  ),
              ],
            ),
            SettingsRow(
              key: const ValueKey('webhook-create-button'),
              icon: Icons.add_rounded,
              tone: SettingsTone.accent,
              title: tr('New webhook'),
              showChevron: false,
              onTap: _busy || list == null || list.length >= 10
                  ? null
                  : _create,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Text(
            tr(
              'Webhooks let other services post messages here. Anyone with a '
              "webhook's URL can post, so keep it secret.",
            ),
            style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// One webhook: bot tile, name, who made it and when it was last used,
/// and its actions.
class _WebhookRow extends StatelessWidget {
  const _WebhookRow({
    required this.webhook,
    required this.busy,
    required this.onMenu,
    super.key,
  });

  final ChannelWebhook webhook;
  final bool busy;
  final ValueChanged<Offset?> onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          ThingAvatar(
            label: webhook.name,
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
                Text(
                  webhook.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _webhookSubtitle(webhook),
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ],
            ),
          ),
          Builder(
            builder: (buttonContext) => WeCordIconButton(
              key: ValueKey('webhook-menu-${webhook.id}'),
              tooltip: tr('Webhook actions'),
              icon: Icons.more_horiz_rounded,
              variant: WeCordButtonVariant.ghost,
              size: 36,
              onPressed: busy
                  ? null
                  : () {
                      final box =
                          buttonContext.findRenderObject() as RenderBox?;
                      onMenu(
                        box?.localToGlobal(box.size.bottomRight(Offset.zero)),
                      );
                    },
            ),
          ),
        ],
      ),
    );
  }
}

class _WebhookNote extends StatelessWidget {
  const _WebhookNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Text(
        text,
        style: TextStyle(fontSize: 14, color: context.tokens.colors.muted),
      ),
    );
  }
}

/// "Created by Ada · Last used 5m ago" (or "Never used").
String _webhookSubtitle(ChannelWebhook webhook) {
  final creator = webhook.creatorName?.trim();
  final lastUsedAt = webhook.lastUsedAt;
  return [
    if (creator != null && creator.isNotEmpty)
      tr('Created by {name}', {'name': creator}),
    lastUsedAt == null
        ? tr('Never used')
        : tr('Last used {time}', {'time': formatThreadActivity(lastUsedAt)}),
  ].join(' · ');
}

class _WebhookNameDialog extends StatefulWidget {
  const _WebhookNameDialog({
    required this.title,
    required this.action,
    required this.initialName,
  });

  final String title;
  final String action;
  final String initialName;

  @override
  State<_WebhookNameDialog> createState() => _WebhookNameDialogState();
}

class _WebhookNameDialogState extends State<_WebhookNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = tr('Name the webhook.'));
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: widget.title,
      content: WeCordTextField(
        fieldKey: const ValueKey('webhook-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: ChannelWebhook.maxNameLength,
        label: tr('Name'),
        errorText: _errorText,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('webhook-name-submit'),
          label: widget.action,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Shows a webhook URL once, with a copy button and a warning.
class _WebhookUrlDialog extends StatelessWidget {
  const _WebhookUrlDialog({required this.title, required this.url});

  final String title;

  /// Null when the app does not know its Supabase URL.
  final String? url;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final url = this.url;
    return CircleDialog(
      title: title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.warningSoft,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 20,
                  color: c.warningText,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(
                      'Copy this URL now: it is shown only once. Anyone with it '
                      'can post in this channel.',
                    ),
                    style: TextStyle(fontSize: 13.5, color: c.ink, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.raised,
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            child: SelectableText(
              url ?? tr('The app does not know its server address.'),
              key: const ValueKey('webhook-url'),
              style: TextStyle(
                fontSize: 12.5,
                fontFamily: 'monospace',
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'POST JSON like {"content": "Hello"} to it; "username" and '
              '"avatar_url" are optional.',
            ),
            style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
          ),
        ],
      ),
      actions: [
        if (url != null)
          CircleDialogAction(
            key: const ValueKey('webhook-copy-url'),
            label: tr('Copy'),
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: url)));
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text(tr('URL copied.'))));
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
