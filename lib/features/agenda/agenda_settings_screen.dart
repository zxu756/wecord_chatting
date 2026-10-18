import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/agenda/calendar_feed_repository.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/message_markdown_text.dart'
    show linkLauncherProvider;
import 'package:wecord/features/circles/circle_ui.dart'
    show confirmCircleAction;
import 'package:wecord/features/later/later_time.dart' show describeWhen;
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings -> Calendar subscription.
void openAgendaSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const AgendaSettingsScreen()),
  );
}

/// The "Calendar subscription" row of Settings.
class AgendaSettingsRow extends StatelessWidget {
  const AgendaSettingsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: const ValueKey('agenda-settings-tile'),
      icon: Icons.event_repeat_outlined,
      title: tr('Calendar subscription'),
      subtitle: tr('Show your agenda in Apple or Google Calendar'),
      onTap: () => openAgendaSettings(context),
    );
  }
}

/// Settings -> Calendar subscription: a secret link that Apple Calendar,
/// Google Calendar or any calendar app subscribes to, to show the next 60
/// days of the person's events and tasks. The link can be copied, reset (the
/// old one stops working) or turned off, and shows only times and
/// conversation names unless the person chooses to include the details.
class AgendaSettingsScreen extends ConsumerStatefulWidget {
  const AgendaSettingsScreen({super.key});

  @override
  ConsumerState<AgendaSettingsScreen> createState() =>
      _AgendaSettingsScreenState();
}

class _AgendaSettingsScreenState extends ConsumerState<AgendaSettingsScreen> {
  /// The link secret kept on this device, when there is one.
  String? _token;
  var _tokenLoaded = false;
  var _busy = false;
  String? _error;
  String? _notice;

  String? get _userId => ref.read(authStateProvider).value?.id;

  @override
  void initState() {
    super.initState();
    unawaited(_loadToken());
  }

  Future<void> _loadToken() async {
    final userId = _userId;
    final token = userId == null
        ? null
        : await ref.read(calendarFeedTokenStoreProvider).read(userId);
    if (mounted) {
      setState(() {
        _token = token;
        _tokenLoaded = true;
      });
    }
  }

  int get _offsetMinutes => clock.now().timeZoneOffset.inMinutes;
  String get _language => AppStrings.isChinese ? 'zh' : 'en';

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(() => _error = failure);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _create({required bool includeContent}) {
    return _run(() async {
      final token = await ref
          .read(calendarFeedRepositoryProvider)
          .createToken(
            includeContent: includeContent,
            utcOffsetMinutes: _offsetMinutes,
            language: _language,
          );
      final userId = _userId;
      if (userId != null) {
        await ref.read(calendarFeedTokenStoreProvider).write(userId, token);
      }
      ref.invalidate(calendarFeedSettingsProvider);
      await ref.read(calendarFeedSettingsProvider.future);
      if (mounted) {
        setState(() => _token = token);
      }
    }, tr('Could not make the link. Try again.'));
  }

  Future<void> _reset(CalendarFeedSettings settings) async {
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Reset the link?'),
      message: tr(
        'The old link stops working. Calendars that use it will need the new '
        'link.',
      ),
      confirmLabel: tr('Reset link'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _create(includeContent: settings.includeContent);
    if (mounted && _error == null) {
      setState(() => _notice = tr('New link made. The old one is off.'));
    }
  }

  Future<void> _turnOff() async {
    final confirmed = await confirmCircleAction(
      context,
      title: tr('Turn off the subscription?'),
      message: tr('The link stops working. You can make a new one any time.'),
      confirmLabel: tr('Turn off'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    await _run(() async {
      await ref.read(calendarFeedRepositoryProvider).delete();
      final userId = _userId;
      if (userId != null) {
        await ref.read(calendarFeedTokenStoreProvider).clear(userId);
      }
      ref.invalidate(calendarFeedSettingsProvider);
      await ref.read(calendarFeedSettingsProvider.future);
      if (mounted) {
        setState(() => _token = null);
      }
    }, tr('Could not turn it off. Try again.'));
  }

  Future<void> _setContent(bool value) {
    return _run(() async {
      await ref
          .read(calendarFeedRepositoryProvider)
          .setOptions(
            includeContent: value,
            utcOffsetMinutes: _offsetMinutes,
            language: _language,
          );
      ref.invalidate(calendarFeedSettingsProvider);
      await ref.read(calendarFeedSettingsProvider.future);
    }, tr('Could not save. Try again.'));
  }

  Uri? _feedUrl() {
    final token = _token;
    final base = ref.read(appConfigProvider)?.supabaseUrl;
    if (token == null || base == null) {
      return null;
    }
    return calendarFeedUrl(base, token);
  }

  Future<void> _copy() async {
    final url = _feedUrl();
    if (url == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: url.toString()));
    if (mounted) {
      setState(() {
        _error = null;
        _notice = tr('Link copied. Paste it into your calendar app.');
      });
    }
  }

  Future<void> _subscribe() async {
    final url = _feedUrl();
    if (url == null) {
      return;
    }
    try {
      await ref.read(linkLauncherProvider)(
        context,
        calendarFeedSubscribeUrl(url),
      );
    } on Object {
      if (mounted) {
        setState(
          () => _error = tr(
            'No calendar app opened. Copy the link and add it as a '
            'subscription instead.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final settings = ref.watch(calendarFeedSettingsProvider);
    final value = settings.value;
    final hasUrl = _feedUrl() != null;

    final List<Widget> children = [
      const SizedBox(height: 12),
      _Explainer(
        text: tr(
          'Subscribe to see your events and tasks for the next 60 days in '
          'Apple Calendar, Google Calendar or any calendar app. Anyone with '
          'the link can see them, so keep it private.',
        ),
      ),
      const SizedBox(height: 12),
      if (_error case final error?)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Semantics(
            liveRegion: true,
            child: Text(
              error,
              key: const ValueKey('agenda-settings-error'),
              style: TextStyle(fontSize: 13.5, color: c.dangerText),
            ),
          ),
        ),
      if (_notice case final notice?)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Semantics(
            liveRegion: true,
            child: Text(
              notice,
              key: const ValueKey('agenda-settings-notice'),
              style: TextStyle(fontSize: 13.5, color: c.successText),
            ),
          ),
        ),
      if (value == null && settings.isLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (value == null)
        Text(
          tr('Could not load the subscription.'),
          style: TextStyle(color: c.dangerText),
        )
      else if (!value.enabled)
        WeCordButton(
          key: const ValueKey('agenda-create-link'),
          label: tr('Create link'),
          icon: Icons.link_rounded,
          size: WeCordButtonSize.large,
          expand: true,
          loading: _busy,
          onPressed: _busy ? null : () => _create(includeContent: false),
        )
      else ...[
        _LinkBox(
          url: _tokenLoaded ? _feedUrl() : null,
          missing: _tokenLoaded && !hasUrl,
        ),
        const SizedBox(height: 12),
        if (hasUrl) ...[
          WeCordButton(
            key: const ValueKey('agenda-subscribe'),
            label: tr('Add to calendar'),
            icon: Icons.event_available_outlined,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: _busy ? null : _subscribe,
          ),
          const SizedBox(height: 10),
          WeCordButton(
            key: const ValueKey('agenda-copy-link'),
            label: tr('Copy link'),
            icon: Icons.copy_rounded,
            variant: WeCordButtonVariant.secondary,
            size: WeCordButtonSize.large,
            expand: true,
            onPressed: _busy ? null : _copy,
          ),
        ],
        const SizedBox(height: 16),
        SettingsGroup(
          footer: value.includeContent
              ? tr(
                  'Your calendar shows titles, places and details. Anyone '
                  'with the link can read them.',
                )
              : tr(
                  'Your calendar shows only the time and the name of the '
                  'conversation, such as "Event · Climbing crew".',
                ),
          children: [
            SettingsRow.toggle(
              key: const ValueKey('agenda-include-content'),
              icon: Icons.subject_rounded,
              title: tr('Include titles and details'),
              value: value.includeContent,
              onChanged: _busy ? null : _setContent,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          footer: _lastUsed(context, value),
          children: [
            SettingsRow(
              key: const ValueKey('agenda-reset-link'),
              icon: Icons.autorenew_rounded,
              title: tr('Reset link'),
              subtitle: tr('Makes a new link and turns the old one off'),
              showChevron: false,
              onTap: _busy ? null : () => _reset(value),
            ),
            SettingsRow(
              key: const ValueKey('agenda-turn-off'),
              icon: Icons.link_off_rounded,
              title: tr('Turn off subscription'),
              destructive: true,
              showChevron: false,
              onTap: _busy ? null : _turnOff,
            ),
          ],
        ),
      ],
    ];

    return SettingsPage(
      key: const ValueKey('agenda-settings-screen'),
      title: tr('Calendar subscription'),
      children: children,
    );
  }

  String? _lastUsed(BuildContext context, CalendarFeedSettings settings) {
    final used = settings.lastUsedAt;
    if (used == null) {
      return tr('No calendar app has fetched it yet.');
    }
    return tr('Last fetched by a calendar app: {when}', {
      'when': describeWhen(
        MaterialLocalizations.of(context),
        used.toLocal(),
        clock.now(),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      ),
    });
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_note_outlined, size: 22, color: c.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: c.ink, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkBox extends StatelessWidget {
  const _LinkBox({required this.url, required this.missing});

  final Uri? url;

  /// A link exists on the server, but this device does not have it.
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: missing
          ? Text(
              tr(
                'The link was made on another device and is not kept on '
                'this one. Reset it to get a new link here.',
              ),
              key: const ValueKey('agenda-link-elsewhere'),
              style: TextStyle(fontSize: 14, color: c.muted, height: 1.45),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('Your link'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.subtle,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(WeCordRadii.md),
                  ),
                  child: SelectableText(
                    url?.toString() ?? '…',
                    key: const ValueKey('agenda-link'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontFamily: 'monospace',
                      color: c.ink,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
