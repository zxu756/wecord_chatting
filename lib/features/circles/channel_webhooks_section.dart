import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/models/channel_webhook.dart';
import 'package:wecord/shared/models/circle.dart';

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
    final name = await showDialog<String>(
      context: context,
      builder: (context) => const _WebhookNameDialog(
        title: 'New webhook',
        action: 'Create',
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
      failure: 'Could not create the webhook. Try again.',
    );
    if (secret != null && mounted) {
      await _showUrl(secret, created: true);
    }
  }

  Future<void> _rename(ChannelWebhook webhook) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _WebhookNameDialog(
        title: 'Rename webhook',
        action: 'Save',
        initialName: webhook.name,
      ),
    );
    if (name == null || name == webhook.name || !mounted) {
      return;
    }
    await _run(
      (repository) =>
          repository.renameChannelWebhook(webhookId: webhook.id, name: name),
      failure: 'Could not rename the webhook. Try again.',
    );
  }

  Future<void> _regenerate(ChannelWebhook webhook) async {
    final confirmed = await _confirm(
      title: 'Regenerate URL',
      message:
          'The current URL of "${webhook.name}" stops working right away. '
          'Services using it need the new one.',
      action: 'Regenerate',
    );
    if (!confirmed || !mounted) {
      return;
    }
    final secret = await _run(
      (repository) => repository.regenerateWebhookToken(webhook.id),
      failure: 'Could not regenerate the URL. Try again.',
    );
    if (secret != null && mounted) {
      await _showUrl(secret, created: false);
    }
  }

  Future<void> _delete(ChannelWebhook webhook) async {
    final confirmed = await _confirm(
      title: 'Delete webhook',
      message:
          'Delete "${webhook.name}"? Its URL stops working. Messages it '
          'posted stay.',
      action: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.deleteChannelWebhook(webhook.id),
      failure: 'Could not delete the webhook. Try again.',
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('webhook-confirm'),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _showUrl(ChannelWebhookSecret secret, {required bool created}) {
    final supabaseUrl = ref.read(appConfigProvider)?.supabaseUrl;
    return showDialog<void>(
      context: context,
      builder: (context) => _WebhookUrlDialog(
        title: created ? 'Webhook created' : 'New webhook URL',
        url: supabaseUrl == null ? null : secret.urlFor(supabaseUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final webhooks = ref.watch(channelWebhooksProvider(widget.channel.id));
    return Column(
      key: const ValueKey('channel-integrations'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Integrations',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Webhooks let other services post messages here. Anyone with a '
            "webhook's URL can post, so keep it secret.",
            style: theme.textTheme.bodySmall,
          ),
        ),
        webhooks.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Could not load webhooks.'),
          ),
          data: (webhooks) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (webhooks.isEmpty)
                const ListTile(title: Text('No webhooks yet.')),
              for (final webhook in webhooks)
                ListTile(
                  key: ValueKey('webhook-${webhook.id}'),
                  leading: const CircleAvatar(child: Icon(Icons.smart_toy)),
                  title: Text(
                    webhook.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(_webhookSubtitle(webhook)),
                  trailing: PopupMenuButton<_WebhookAction>(
                    key: ValueKey('webhook-menu-${webhook.id}'),
                    tooltip: 'Webhook actions',
                    enabled: !_busy,
                    onSelected: (action) => unawaited(switch (action) {
                      _WebhookAction.rename => _rename(webhook),
                      _WebhookAction.regenerate => _regenerate(webhook),
                      _WebhookAction.delete => _delete(webhook),
                    }),
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _WebhookAction.rename,
                        child: Text('Rename'),
                      ),
                      PopupMenuItem(
                        value: _WebhookAction.regenerate,
                        child: Text('Regenerate URL'),
                      ),
                      PopupMenuItem(
                        value: _WebhookAction.delete,
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    key: const ValueKey('webhook-create-button'),
                    onPressed: _busy || webhooks.length >= 10 ? null : _create,
                    icon: const Icon(Icons.add),
                    label: const Text('New webhook'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Created by Ada · Last used 5m ago" (or "Never used").
String _webhookSubtitle(ChannelWebhook webhook) {
  final creator = webhook.creatorName?.trim();
  final lastUsedAt = webhook.lastUsedAt;
  return [
    if (creator != null && creator.isNotEmpty) 'Created by $creator',
    lastUsedAt == null
        ? 'Never used'
        : 'Last used ${formatThreadActivity(lastUsedAt)}',
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
      setState(() => _errorText = 'Name the webhook.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('webhook-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: ChannelWebhook.maxNameLength,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: 'Name',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('webhook-name-submit'),
          onPressed: _submit,
          child: Text(widget.action),
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
    final theme = Theme.of(context);
    final url = this.url;
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Copy this URL now: it is shown only once. Anyone with it '
                  'can post in this channel.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              url ?? 'The app does not know its server address.',
              key: const ValueKey('webhook-url'),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'POST JSON like {"content": "Hello"} to it; "username" and '
            '"avatar_url" are optional.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        if (url != null)
          TextButton.icon(
            key: const ValueKey('webhook-copy-url'),
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: url)));
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(const SnackBar(content: Text('URL copied.')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
