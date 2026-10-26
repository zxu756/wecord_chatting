import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/developer/developer_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What each kind of event means, in words.
String botEventLabel(String name) {
  return switch (name) {
    'message.created' => tr('New messages'),
    'message.mentioned' => tr('Messages that mention the bot'),
    'message.updated' => tr('Edited messages'),
    'message.deleted' => tr('Deleted messages'),
    'reaction.added' => tr('Reactions added'),
    'member.joined' => tr('Members who joined'),
    'member.left' => tr('Members who left'),
    'interaction.created' => tr('Button presses and slash commands'),
    _ => name,
  };
}

/// The kinds a new event address starts with.
const defaultBotEvents = <String>[
  'message.created',
  'message.mentioned',
  'interaction.created',
];

/// Developer → a bot → Event address: where WeCord sends what happens in the
/// bot's chats (signed with a secret) and which kinds of event it wants.
/// Saving a new address shows the secret once.
Future<void> showBotEventsDialog(
  BuildContext context,
  WidgetRef ref,
  DeveloperBot bot,
) async {
  final repository = ref.read(developerRepositoryProvider);
  var current = bot.events;
  while (true) {
    if (!context.mounted) {
      return;
    }
    final input = await showCircleDialog<_EventsInput>(
      context,
      builder: (context) => _EventsDialog(bot: bot, current: current),
    );
    if (input == null || !context.mounted) {
      return;
    }
    try {
      current = await repository.setSubscription(
        bot.id,
        url: input.url,
        events: input.events,
      );
      ref.invalidate(developerBotsProvider);
      if (current.secret != null && context.mounted) {
        await showBotEventSecret(context, current.secret!, created: true);
      }
      return;
    } on PostgrestException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              error.code == '22023'
                  ? tr(
                      'That address cannot be used. It must be the https '
                      'address of a website (no IP addresses, no ports, no '
                      'inner names).',
                    )
                  : tr('Could not save the event address. Try again.'),
            ),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(tr('Could not save the event address. Try again.')),
          ),
        );
      }
    }
  }
}

class _EventsInput {
  const _EventsInput(this.url, this.events);

  final String url;
  final List<String> events;
}

class _EventsDialog extends StatefulWidget {
  const _EventsDialog({required this.bot, required this.current});

  final DeveloperBot bot;
  final BotEventSubscription current;

  @override
  State<_EventsDialog> createState() => _EventsDialogState();
}

class _EventsDialogState extends State<_EventsDialog> {
  late final _url = TextEditingController(text: widget.current.url ?? '');
  late final Set<String> _events = {
    ...widget.current.isSet ? widget.current.events : defaultBotEvents,
  };
  final _fieldKey = GlobalKey();
  String? _error;
  String? _eventsError;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// The address is at the top of a dialog that can be taller than the
  /// screen; bring it back into view so its error is seen.
  void _showAddressError(String message) {
    setState(() => _error = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final field = _fieldKey.currentContext;
      if (mounted && field != null) {
        unawaited(
          Scrollable.ensureVisible(
            field,
            duration: const Duration(milliseconds: 200),
          ),
        );
      }
    });
  }

  void _save() {
    final text = _url.text.trim();
    if (!text.toLowerCase().startsWith('https://')) {
      _showAddressError(tr('The address must start with https://'));
      return;
    }
    if (_events.isEmpty) {
      setState(() => _eventsError = tr('Choose at least one kind of event.'));
      return;
    }
    Navigator.of(context).pop(
      _EventsInput(text, [
        for (final name in botEventKinds)
          if (_events.contains(name)) name,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CircleDialog(
      title: tr('Event address'),
      message: tr(
        'WeCord sends the chosen events of {name}\'s chats to this address '
        'as they happen, signed with a secret. Only chats the bot is in and '
        'messages it may read are included.',
        {'name': widget.bot.name},
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            key: _fieldKey,
            fieldKey: const ValueKey('bot-events-field'),
            controller: _url,
            label: tr('https address'),
            hint: tr('https://bots.example.com/events'),
            keyboardType: TextInputType.url,
            errorText: _error,
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              tr('Events to send'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
          ),
          SettingsGroup(
            color: c.raised,
            separatorIndent: 14,
            children: [
              for (final name in botEventKinds)
                SettingsRow.toggle(
                  key: ValueKey('bot-event-$name'),
                  title: botEventLabel(name),
                  value: _events.contains(name),
                  onChanged: (on) => setState(() {
                    if (on) {
                      _events.add(name);
                    } else {
                      _events.remove(name);
                    }
                    _eventsError = null;
                  }),
                ),
            ],
          ),
          if (_eventsError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
              child: Text(
                _eventsError!,
                key: const ValueKey('bot-events-error'),
                style: TextStyle(fontSize: 13, color: c.dangerText),
              ),
            ),
        ],
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('bot-events-save'),
          label: tr('Save'),
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Shows the secret that signs the events, once.
Future<void> showBotEventSecret(
  BuildContext context,
  String secret, {
  required bool created,
}) {
  return showCircleDialog<void>(
    context,
    builder: (context) {
      final c = context.tokens.colors;
      return CircleDialog(
        title: created ? tr('Event secret') : tr('New event secret'),
        message: tr(
          'Copy the secret now: it is shown only once. Use it to check the '
          'X-WeCord-Signature of every event.',
        ),
        content: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(WeCordRadii.md),
          ),
          child: SelectableText(
            secret,
            key: const ValueKey('bot-events-secret'),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: c.ink,
            ),
          ),
        ),
        actions: [
          CircleDialogAction(
            key: const ValueKey('bot-events-secret-copy'),
            label: tr('Copy'),
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: secret)));
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text(tr('Secret copied.'))));
            },
          ),
          CircleDialogAction.primary(
            label: tr('Done'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    },
  );
}
