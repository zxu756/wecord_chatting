import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/circles/circle_bot_repository.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Circle settings → Bots → a bot → Callback address: where WeCord sends the
/// bot's button presses and slash commands as they happen (signed with a
/// secret), instead of the bot polling for them.
Future<void> showBotCallbackDialog(
  BuildContext context,
  WidgetRef ref,
  CircleBot bot,
) async {
  final repository = ref.read(circleBotRepositoryProvider);
  BotCallback current;
  try {
    current = await repository.getCallback(bot.id);
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(tr('Could not load the callback. Try again.'))),
      );
    }
    return;
  }
  while (true) {
    if (!context.mounted) {
      return;
    }
    final action = await showCircleDialog<_CallbackResult>(
      context,
      builder: (context) => _CallbackDialog(bot: bot, current: current),
    );
    if (action == null || !context.mounted) {
      return;
    }
    try {
      switch (action) {
        case _Save(:final url):
          current = await repository.setCallback(bot.id, url);
          if (current.secret != null && context.mounted) {
            await _showSecret(context, current.secret!, created: true);
          }
        case _Rotate():
          final rotated = await repository.rotateCallbackSecret(bot.id);
          if (rotated.secret != null && context.mounted) {
            await _showSecret(context, rotated.secret!, created: false);
          }
        case _Clear():
          await repository.clearCallback(bot.id);
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
                  : tr('Could not save the callback. Try again.'),
            ),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(tr('Could not save the callback. Try again.')),
          ),
        );
      }
    }
  }
}

sealed class _CallbackResult {
  const _CallbackResult();
}

class _Save extends _CallbackResult {
  const _Save(this.url);

  final String url;
}

class _Rotate extends _CallbackResult {
  const _Rotate();
}

class _Clear extends _CallbackResult {
  const _Clear();
}

class _CallbackDialog extends StatefulWidget {
  const _CallbackDialog({required this.bot, required this.current});

  final CircleBot bot;
  final BotCallback current;

  @override
  State<_CallbackDialog> createState() => _CallbackDialogState();
}

class _CallbackDialogState extends State<_CallbackDialog> {
  late final _url = TextEditingController(text: widget.current.url ?? '');
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _save() {
    final text = _url.text.trim();
    if (!text.toLowerCase().startsWith('https://')) {
      setState(() => _error = tr('The address must start with https://'));
      return;
    }
    Navigator.of(context).pop(_Save(text));
  }

  String? get _status {
    final current = widget.current;
    if (!current.isSet) {
      return null;
    }
    if (!current.enabled) {
      return tr(
        'Paused: too many sends failed in a row. Save the address again to '
        'turn it back on. Meanwhile the bot can poll.',
      );
    }
    if (current.lastError != null) {
      return tr('The last send failed ({reason}). WeCord tries again.', {
        'reason': current.lastError,
      });
    }
    if (current.lastSuccessAt != null) {
      return tr('Working. The last send went through.');
    }
    return tr('Nothing has been sent yet.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final current = widget.current;
    final status = _status;
    return CircleDialog(
      title: tr('Callback address'),
      message: tr(
        'WeCord sends {name}\'s button presses and slash commands to this '
        'address as they happen, signed with a secret. Without one, the bot '
        'asks for them by polling.',
        {'name': widget.bot.name},
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('bot-callback-field'),
            controller: _url,
            autofocus: true,
            label: tr('https address'),
            hint: tr('https://bots.example.com/wecord'),
            keyboardType: TextInputType.url,
            errorText: _error,
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: (_) => _save(),
          ),
          if (status != null) ...[
            const SizedBox(height: 10),
            Text(
              status,
              key: const ValueKey('bot-callback-status'),
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: current.enabled && current.lastError == null
                    ? c.muted
                    : c.dangerText,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (current.isSet)
          CircleDialogAction.danger(
            key: const ValueKey('bot-callback-clear'),
            label: tr('Remove'),
            onPressed: () => Navigator.of(context).pop(const _Clear()),
          ),
        if (current.isSet)
          CircleDialogAction(
            key: const ValueKey('bot-callback-rotate'),
            label: tr('Reset secret'),
            onPressed: () => Navigator.of(context).pop(const _Rotate()),
          ),
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('bot-callback-save'),
          label: tr('Save'),
          onPressed: _save,
        ),
      ],
    );
  }
}

Future<void> _showSecret(
  BuildContext context,
  String secret, {
  required bool created,
}) {
  return showCircleDialog<void>(
    context,
    builder: (context) {
      final c = context.tokens.colors;
      return CircleDialog(
        title: created ? tr('Callback secret') : tr('New callback secret'),
        message: tr(
          'Copy the secret now: it is shown only once. Use it to check the '
          'X-WeCord-Signature of every request.',
        ),
        content: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(WeCordRadii.md),
          ),
          child: SelectableText(
            secret,
            key: const ValueKey('bot-callback-secret'),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: c.ink,
            ),
          ),
        ),
        actions: [
          CircleDialogAction(
            key: const ValueKey('bot-callback-secret-copy'),
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
