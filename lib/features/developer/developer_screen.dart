import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/developer/developer_bot_screen.dart';
import 'package:wecord/features/developer/developer_repository.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/config/site_url.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

void openDeveloper(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const DeveloperScreen()),
  );
}

/// Opens the bot API documentation; tests swap it out.
final developerDocsLauncherProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Where the documentation of the bot API lives.
Uri developerDocsUri() => Uri.parse('${authRedirectUrl()}/developers/');

/// "Just now", "5 minutes ago", "3 hours ago", "2 days ago" for [at].
String developerTimeAgo(DateTime at, {DateTime? now}) {
  final age = (now ?? DateTime.now()).toUtc().difference(at.toUtc());
  if (age.inMinutes < 1) {
    return tr('Just now');
  }
  if (age.inMinutes < 60) {
    return tr('{count} minutes ago', {'count': age.inMinutes});
  }
  if (age.inHours < 24) {
    return age.inHours == 1
        ? tr('1 hour ago')
        : tr('{count} hours ago', {'count': age.inHours});
  }
  return age.inDays == 1
      ? tr('1 day ago')
      : tr('{count} days ago', {'count': age.inDays});
}

/// Settings → Privacy: the Developer entry, only for people who manage a
/// circle (and so can have bots). Nothing at all for everyone else.
class DeveloperSettingsGroup extends ConsumerWidget {
  const DeveloperSettingsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(developerAccessProvider).value != true) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const ValueKey('developer-tile'),
              icon: Icons.code_rounded,
              title: tr('Developer'),
              subtitle: tr('Bots, event subscriptions and the bot API'),
              onTap: () => openDeveloper(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// Settings → Developer: the bots of the circles the person manages, and the
/// way into each one's token, event address, availability and recent calls.
class DeveloperScreen extends ConsumerWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final access = ref.watch(developerAccessProvider);
    final bots = ref.watch(developerBotsProvider);
    return SettingsPage(
      title: tr('Developer'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 12),
          child: Text(
            tr(
              'Bots are programs that act in your circles. Each bot has a '
              'token to call the bot API and can get events as they '
              'happen. Only people who manage a circle can see this page.',
            ),
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
        ),
        SettingsGroup(
          children: [
            SettingsRow(
              key: const ValueKey('developer-docs'),
              icon: Icons.menu_book_outlined,
              title: tr('Bot API documentation'),
              subtitle: tr('Endpoints, events and examples'),
              showChevron: false,
              trailing: Icon(
                Icons.open_in_new_rounded,
                size: 18,
                color: c.subtle,
              ),
              onTap: () => unawaited(
                ref.read(developerDocsLauncherProvider)(developerDocsUri()),
              ),
            ),
          ],
        ),
        SettingsSectionHeader(tr('Your bots')),
        if (access.value == false)
          _Note(
            key: const ValueKey('developer-no-access'),
            text: tr('Only people who manage a circle can use this page.'),
          )
        else
          bots.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => SettingsGroup(
              children: [
                SettingsRow(
                  key: const ValueKey('developer-bots-error'),
                  icon: Icons.error_outline,
                  tone: SettingsTone.danger,
                  title: tr('Could not load your bots.'),
                  subtitle: tr('Tap to try again.'),
                  showChevron: false,
                  onTap: () => ref.invalidate(developerBotsProvider),
                ),
              ],
            ),
            data: (list) => list.isEmpty
                ? _Note(
                    key: const ValueKey('developer-no-bots'),
                    text: tr(
                      'No bots yet. Make one in a circle: Circle settings, '
                      'Bots, New bot.',
                    ),
                  )
                : SettingsGroup(
                    children: [for (final bot in list) _BotRow(bot: bot)],
                  ),
          ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
      ),
    );
  }
}

/// How a bot's events are doing, in a few words.
String developerEventsStatus(BotEventSubscription events) {
  if (!events.isSet) {
    return tr('Events: not set');
  }
  return events.enabled ? tr('Events: on') : tr('Events: paused');
}

class _BotRow extends StatelessWidget {
  const _BotRow({required this.bot});

  final DeveloperBot bot;

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: ValueKey('developer-bot-${bot.id}'),
      icon: Icons.smart_toy_outlined,
      tone: bot.bot.hasToken ? SettingsTone.accent : SettingsTone.neutral,
      title: bot.name,
      subtitle: [
        bot.circleName,
        if (!bot.bot.hasToken)
          tr('Token revoked')
        else
          developerEventsStatus(bot.events),
        tr('{count} calls in the last day', {'count': bot.callsLastDay}),
      ].where((part) => part.isNotEmpty).join(' · '),
      onTap: () => openDeveloperBot(context, bot.id),
    );
  }
}
