// Channel settings -> RSS feeds and GitHub (roadmap I6): the feeds a channel
// follows and the GitHub repositories that post into it. Shown to members who
// can manage webhooks, below the channel's webhooks.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/thread/thread_text.dart'
    show formatThreadActivity;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/integrations/integrations_repository.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The words for an event of a GitHub connection.
String githubEventLabel(String name) => switch (name) {
  'push' => tr('Pushes'),
  'pull_request' => tr('Pull requests'),
  'issues' => tr('Issues'),
  'issue_comment' => tr('Comments'),
  'release' => tr('Releases'),
  'workflow_run' => tr('Workflow runs'),
  _ => name,
};

/// What went wrong with the last read of a feed, in a few words.
String feedErrorLabel(String? code) {
  if (code == null || code.isEmpty) {
    return tr('The feed could not be read.');
  }
  if (code.startsWith('http_')) {
    return tr('The site answered with an error ({code}).', {
      'code': code.substring(5),
    });
  }
  return switch (code) {
    'not_a_feed' => tr('That address is not a feed.'),
    'bad_xml' || 'doctype_refused' => tr("The feed's text is not valid."),
    'timeout' => tr('The site took too long to answer.'),
    'too_large' => tr('The feed is too big.'),
    'rate_limited' => tr('The site asked us to slow down.'),
    _ => tr('The feed could not be read.'),
  };
}

String _pausedLabel(PausedReason? reason) => switch (reason) {
  PausedReason.failing => tr('Paused: it kept failing. Resume to try again.'),
  PausedReason.creatorLostAccess => tr(
    'Paused: the person who added it can no longer post here.',
  ),
  PausedReason.creatorGone => tr(
    'Paused: the person who added it left WeCord.',
  ),
  null => tr('Paused'),
};

String _problemText(Object error, String fallback) {
  if (error is IntegrationException) {
    return switch (error.problem) {
      IntegrationProblem.badAddress => tr(
        'Use a public address that starts with https://.',
      ),
      IntegrationProblem.limit => tr(
        'This circle or channel has all it can have. Remove one first.',
      ),
      IntegrationProblem.duplicate => tr(
        'This channel already follows that feed.',
      ),
      IntegrationProblem.notAllowed => tr(
        'You can no longer manage this channel.',
      ),
      IntegrationProblem.invalid => fallback,
    };
  }
  return fallback;
}

/// Examples in the fields: addresses and names, the same in every language.
const _exampleFeed = 'https://example.com/feed.xml';
const _exampleRepository = 'wecord/app';

enum _FeedAction { toggle, remove }

enum _HookAction { edit, toggle, regenerate, remove }

class ChannelConnectionsSection extends ConsumerStatefulWidget {
  const ChannelConnectionsSection({required this.channel, super.key});

  final CircleChannel channel;

  @override
  ConsumerState<ChannelConnectionsSection> createState() =>
      _ChannelConnectionsSectionState();
}

class _ChannelConnectionsSectionState
    extends ConsumerState<ChannelConnectionsSection> {
  var _busy = false;

  String get _channelId => widget.channel.id;

  Future<T?> _run<T>(
    Future<T> Function(IntegrationsRepository repository) action, {
    required String failure,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _busy = true);
    try {
      final result = await action(ref.read(integrationsRepositoryProvider));
      ref
        ..invalidate(channelFeedsProvider(_channelId))
        ..invalidate(githubHooksProvider(_channelId));
      return result;
    } on Object catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text(_problemText(error, failure))),
      );
      return null;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
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
                  key: const ValueKey('integration-confirm'),
                  label: action,
                  onPressed: () => Navigator.of(context).pop(true),
                )
              : CircleDialogAction.primary(
                  key: const ValueKey('integration-confirm'),
                  label: action,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
        ],
      ),
    );
    return confirmed == true;
  }

  // ------------------------------------------------------------- feeds

  Future<void> _addFeed() async {
    final url = await showCircleDialog<String>(
      context,
      builder: (context) => const _FeedAddressDialog(),
    );
    if (url == null || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.addFeed(_channelId, url),
      failure: tr('Could not follow the feed. Try again.'),
    );
  }

  Future<void> _toggleFeed(ChannelFeed feed) async {
    await _run(
      (repository) => repository.setFeedEnabled(feed.id, on: !feed.enabled),
      failure: tr('Could not change the feed. Try again.'),
    );
  }

  Future<void> _removeFeed(ChannelFeed feed) async {
    final confirmed = await _confirm(
      title: tr('Stop following'),
      message: tr('Stop following "{name}"? Messages it posted stay.', {
        'name': feed.displayName,
      }),
      action: tr('Stop following'),
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.removeFeed(feed.id),
      failure: tr('Could not remove the feed. Try again.'),
    );
  }

  Future<void> _feedMenu(ChannelFeed feed, Offset? position) async {
    final action = await showCircleActionMenu<_FeedAction>(
      context,
      title: feed.displayName,
      position: position,
      items: [
        CircleMenuItem(
          value: _FeedAction.toggle,
          icon: feed.enabled
              ? Icons.pause_circle_outline_rounded
              : Icons.play_circle_outline_rounded,
          label: feed.enabled ? tr('Pause') : tr('Resume'),
        ),
        CircleMenuItem(
          value: _FeedAction.remove,
          icon: Icons.delete_outline,
          label: tr('Stop following'),
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) {
      return;
    }
    unawaited(switch (action) {
      _FeedAction.toggle => _toggleFeed(feed),
      _FeedAction.remove => _removeFeed(feed),
    });
  }

  // ------------------------------------------------------------ GitHub

  Future<void> _addHook() async {
    final draft = await showCircleDialog<_HookDraft>(
      context,
      builder: (context) => const _HookDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }
    final hook = await _run(
      (repository) => repository.addHook(
        _channelId,
        label: draft.label,
        events: draft.events,
      ),
      failure: tr('Could not connect GitHub. Try again.'),
    );
    if (hook != null && mounted) {
      await _showSecret(hook, created: true);
    }
  }

  Future<void> _editHook(GithubHook hook) async {
    final draft = await showCircleDialog<_HookDraft>(
      context,
      builder: (context) => _HookDialog(hook: hook),
    );
    if (draft == null || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.updateHook(
        hook.id,
        label: draft.label,
        events: draft.events,
      ),
      failure: tr('Could not save the changes. Try again.'),
    );
  }

  Future<void> _toggleHook(GithubHook hook) async {
    await _run(
      (repository) => repository.setHookEnabled(hook.id, on: !hook.enabled),
      failure: tr('Could not change the connection. Try again.'),
    );
  }

  Future<void> _regenerate(GithubHook hook) async {
    final confirmed = await _confirm(
      title: tr('New secret'),
      message: tr(
        'The current secret of "{name}" stops working right away. GitHub '
        'needs the new one.',
        {'name': hook.label},
      ),
      action: tr('Make a new secret'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    final renewed = await _run(
      (repository) => repository.regenerateSecret(hook.id),
      failure: tr('Could not make a new secret. Try again.'),
    );
    if (renewed != null && mounted) {
      await _showSecret(renewed, created: false);
    }
  }

  Future<void> _removeHook(GithubHook hook) async {
    final confirmed = await _confirm(
      title: tr('Disconnect GitHub'),
      message: tr(
        'Disconnect "{name}"? GitHub can no longer post here. Messages it '
        'posted stay.',
        {'name': hook.label},
      ),
      action: tr('Disconnect'),
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(
      (repository) => repository.removeHook(hook.id),
      failure: tr('Could not disconnect. Try again.'),
    );
  }

  Future<void> _showSecret(GithubHook hook, {required bool created}) {
    final supabaseUrl = ref.read(appConfigProvider)?.supabaseUrl;
    return showCircleDialog<void>(
      context,
      builder: (context) => _GithubSecretDialog(
        title: created ? tr('GitHub connected') : tr('New secret'),
        payloadUrl: supabaseUrl == null
            ? null
            : hook.payloadUrlFor(supabaseUrl),
        secret: hook.secret,
      ),
    );
  }

  Future<void> _hookMenu(GithubHook hook, Offset? position) async {
    final action = await showCircleActionMenu<_HookAction>(
      context,
      title: hook.label,
      position: position,
      items: [
        CircleMenuItem(
          value: _HookAction.edit,
          icon: Icons.edit_outlined,
          label: tr('Name and events'),
        ),
        CircleMenuItem(
          value: _HookAction.toggle,
          icon: hook.enabled
              ? Icons.pause_circle_outline_rounded
              : Icons.play_circle_outline_rounded,
          label: hook.enabled ? tr('Pause') : tr('Resume'),
        ),
        CircleMenuItem(
          value: _HookAction.regenerate,
          icon: Icons.autorenew_rounded,
          label: tr('New secret'),
        ),
        CircleMenuItem(
          value: _HookAction.remove,
          icon: Icons.delete_outline,
          label: tr('Disconnect'),
          destructive: true,
        ),
      ],
    );
    if (action == null || !mounted) {
      return;
    }
    unawaited(switch (action) {
      _HookAction.edit => _editHook(hook),
      _HookAction.toggle => _toggleHook(hook),
      _HookAction.regenerate => _regenerate(hook),
      _HookAction.remove => _removeHook(hook),
    });
  }

  // -------------------------------------------------------------- build

  String _feedSubtitle(ChannelFeed feed) {
    if (!feed.enabled) {
      return _pausedLabel(feed.pausedReason);
    }
    if (feed.hasProblem) {
      return feedErrorLabel(feed.lastError);
    }
    final lastItemAt = feed.lastItemAt;
    if (lastItemAt != null) {
      return tr('Last post {time}', {'time': formatThreadActivity(lastItemAt)});
    }
    return feed.lastSuccessAt == null
        ? tr('Waiting for the first read')
        : tr('Nothing posted yet');
  }

  String _hookSubtitle(GithubHook hook) {
    if (!hook.enabled) {
      return _pausedLabel(hook.pausedReason);
    }
    final events = hook.events.map(githubEventLabel).join(', ');
    final last = hook.lastDeliveryAt;
    return [
      events,
      last == null
          ? tr('Nothing received yet')
          : tr('Last post {time}', {'time': formatThreadActivity(last)}),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final feeds = ref.watch(channelFeedsProvider(_channelId));
    final hooks = ref.watch(githubHooksProvider(_channelId));
    final feedList = feeds.value;
    final hookList = hooks.value;
    Widget note(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
      ),
    );
    return Column(
      key: const ValueKey('channel-connections'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionHeader(tr('RSS feeds')),
        SettingsGroup(
          children: [
            ...feeds.when(
              loading: () => const [_LoadingRow()],
              error: (error, stackTrace) => [
                _NoteRow(tr('Could not load the feeds.')),
              ],
              data: (feeds) => [
                if (feeds.isEmpty) _NoteRow(tr('No feeds yet.')),
                for (final feed in feeds)
                  _ConnectionRow(
                    key: ValueKey('feed-${feed.id}'),
                    icon: Icons.rss_feed_rounded,
                    title: feed.displayName,
                    subtitle: _feedSubtitle(feed),
                    warning: !feed.enabled || feed.hasProblem,
                    menuTooltip: tr('Feed actions'),
                    busy: _busy,
                    onMenu: (position) => _feedMenu(feed, position),
                  ),
              ],
            ),
            SettingsRow(
              key: const ValueKey('feed-add-button'),
              icon: Icons.add_rounded,
              tone: SettingsTone.accent,
              title: tr('Follow a feed'),
              showChevron: false,
              onTap:
                  _busy ||
                      feedList == null ||
                      feedList.length >= maxFeedsPerChannel
                  ? null
                  : _addFeed,
            ),
          ],
        ),
        note(
          tr(
            'New items of a blog or news feed are posted here, a few at a '
            'time, about every 15 minutes. Nothing is posted for what the '
            'feed already had.',
          ),
        ),
        SettingsSectionHeader(tr('GitHub')),
        SettingsGroup(
          children: [
            ...hooks.when(
              loading: () => const [_LoadingRow()],
              error: (error, stackTrace) => [
                _NoteRow(tr('Could not load the connections.')),
              ],
              data: (hooks) => [
                if (hooks.isEmpty) _NoteRow(tr('No repositories yet.')),
                for (final hook in hooks)
                  _ConnectionRow(
                    key: ValueKey('github-${hook.id}'),
                    icon: Icons.code_rounded,
                    title: hook.label,
                    subtitle: _hookSubtitle(hook),
                    warning: !hook.enabled,
                    menuTooltip: tr('Connection actions'),
                    busy: _busy,
                    onMenu: (position) => _hookMenu(hook, position),
                  ),
              ],
            ),
            SettingsRow(
              key: const ValueKey('github-add-button'),
              icon: Icons.add_rounded,
              tone: SettingsTone.accent,
              title: tr('Connect a repository'),
              showChevron: false,
              onTap:
                  _busy ||
                      hookList == null ||
                      hookList.length >= maxGithubPerChannel
                  ? null
                  : _addHook,
            ),
          ],
        ),
        note(
          tr(
            'GitHub posts pushes, pull requests, issues and releases here. '
            "You add the webhook in the repository's settings with the "
            'address and secret shown once after connecting.',
          ),
        ),
      ],
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow(this.text);

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

/// A feed or a GitHub connection: tile, name, a line of state, and a menu.
class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.warning,
    required this.menuTooltip,
    required this.busy,
    required this.onMenu,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Paused or failing: the line is drawn in the warning color.
  final bool warning;
  final String menuTooltip;
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
            label: title,
            size: 36,
            icon: icon,
            color: c.accentSoft,
            foregroundColor: c.accentText,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: warning ? c.warningText : c.muted,
                  ),
                ),
              ],
            ),
          ),
          Builder(
            builder: (buttonContext) => WeCordIconButton(
              tooltip: menuTooltip,
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

/// Asks for the address of a feed.
class _FeedAddressDialog extends StatefulWidget {
  const _FeedAddressDialog();

  @override
  State<_FeedAddressDialog> createState() => _FeedAddressDialogState();
}

class _FeedAddressDialogState extends State<_FeedAddressDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _controller.text.trim();
    if (!url.toLowerCase().startsWith('https://') || url.length < 12) {
      setState(
        () => _errorText = tr('Use an address that starts with https://.'),
      );
      return;
    }
    Navigator.of(context).pop(url);
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: tr('Follow a feed'),
      content: WeCordTextField(
        fieldKey: const ValueKey('feed-url-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        keyboardType: TextInputType.url,
        label: tr('Feed address'),
        hint: _exampleFeed,
        errorText: _errorText,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('feed-url-submit'),
          label: tr('Follow feed'),
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _HookDraft {
  const _HookDraft({required this.label, required this.events});

  final String label;
  final List<String> events;
}

/// A name and the events of a GitHub connection.
class _HookDialog extends StatefulWidget {
  const _HookDialog({this.hook});

  final GithubHook? hook;

  @override
  State<_HookDialog> createState() => _HookDialogState();
}

class _HookDialogState extends State<_HookDialog> {
  late final _controller = TextEditingController(
    text: widget.hook?.label ?? '',
  );
  late final Set<String> _events = {
    ...?widget.hook?.events,
    if (widget.hook == null) ...githubEventNames,
  };
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _controller.text.trim();
    if (label.isEmpty) {
      setState(() => _errorText = tr('Name the connection.'));
      return;
    }
    if (_events.isEmpty) {
      setState(() => _errorText = tr('Choose at least one event.'));
      return;
    }
    Navigator.of(context).pop(
      _HookDraft(
        label: label,
        events: [
          for (final name in githubEventNames)
            if (_events.contains(name)) name,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: widget.hook == null
          ? tr('Connect a repository')
          : tr('Name and events'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('github-name-field'),
            controller: _controller,
            autofocus: widget.hook == null,
            maxLength: 80,
            label: tr('Name'),
            hint: _exampleRepository,
            errorText: _errorText,
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            children: [
              for (final name in githubEventNames)
                SettingsRow.toggle(
                  key: ValueKey('github-event-$name'),
                  title: githubEventLabel(name),
                  value: _events.contains(name),
                  onChanged: (on) => setState(() {
                    if (on) {
                      _events.add(name);
                    } else {
                      _events.remove(name);
                    }
                    _errorText = null;
                  }),
                ),
            ],
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('github-name-submit'),
          label: widget.hook == null ? tr('Connect') : tr('Save'),
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Shows the address and the secret to give GitHub, once.
class _GithubSecretDialog extends StatelessWidget {
  const _GithubSecretDialog({
    required this.title,
    required this.payloadUrl,
    required this.secret,
  });

  final String title;

  /// Null when the app does not know its Supabase URL.
  final String? payloadUrl;
  final String? secret;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    Widget value(Key key, String text) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: SelectableText(
        text,
        key: key,
        style: TextStyle(fontSize: 12.5, fontFamily: 'monospace', color: c.ink),
      ),
    );
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: c.muted,
        ),
      ),
    );
    void copy(BuildContext context, String text, String done) {
      unawaited(Clipboard.setData(ClipboardData(text: text)));
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(done)));
    }

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
                      'Copy the secret now: it is shown only once. Anyone with '
                      'it can post in this channel as GitHub.',
                    ),
                    style: TextStyle(fontSize: 13.5, color: c.ink, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          label(tr('Payload URL')),
          value(
            const ValueKey('github-payload-url'),
            payloadUrl ?? tr('The app does not know its server address.'),
          ),
          label(tr('Secret')),
          value(
            const ValueKey('github-secret'),
            secret ?? tr('No secret to show.'),
          ),
          const SizedBox(height: 10),
          Text(
            tr(
              'In the repository: Settings, Webhooks, Add webhook. Paste the '
              'URL and the secret, set Content type to application/json, and '
              'pick the events you chose here.',
            ),
            style: TextStyle(fontSize: 12.5, color: c.muted, height: 1.4),
          ),
        ],
      ),
      actions: [
        if (payloadUrl case final url?)
          CircleDialogAction(
            key: const ValueKey('github-copy-url'),
            label: tr('Copy URL'),
            onPressed: () => copy(context, url, tr('URL copied.')),
          ),
        if (secret case final text?)
          CircleDialogAction(
            key: const ValueKey('github-copy-secret'),
            label: tr('Copy secret'),
            onPressed: () => copy(context, text, tr('Secret copied.')),
          ),
        CircleDialogAction.primary(
          label: tr('Done'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
