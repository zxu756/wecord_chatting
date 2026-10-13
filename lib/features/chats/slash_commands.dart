import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/shared/models/custom_status.dart';

/// Picks `/roll` results; tests override it with a seeded generator.
final slashCommandRandomProvider = Provider<math.Random>((ref) {
  return math.Random();
});

/// What the composer's conversation allows, which decides the commands
/// offered there.
class SlashCommandContext {
  const SlashCommandContext({
    this.isCircleConversation = false,
    this.canCreatePolls = false,
  });

  /// A circle channel or a thread of one, where `/nick` changes the
  /// current user's circle nickname.
  final bool isCircleConversation;

  /// Polls can be posted here (`/poll`).
  final bool canCreatePolls;
}

enum SlashCommand {
  shrug('shrug', '[message]', r'Appends ¯\_(ツ)_/¯ to your message'),
  tableflip('tableflip', '[message]', 'Appends (╯°□°)╯︵ ┻━┻ to your message'),
  unflip('unflip', '[message]', 'Appends ┬─┬ノ( º _ ºノ) to your message'),
  me('me', '<message>', 'Sends your message in italics'),
  spoiler('spoiler', '<message>', 'Hides your message behind a spoiler'),
  roll('roll', '[sides]', 'Rolls a die (6 sides unless you say otherwise)'),
  poll('poll', '', 'Creates a poll'),
  nick('nick', '<name>', 'Changes your nickname in this circle'),
  status('status', '<emoji> <text>', 'Sets your status, or /status clear');

  const SlashCommand(this.name, this.arguments, this.description);

  /// Typed after the slash.
  final String name;

  /// The arguments shown next to the name in the command list.
  final String arguments;
  final String description;

  /// Whether the command is offered (and run) in [context].
  bool isAvailableIn(SlashCommandContext context) {
    return switch (this) {
      SlashCommand.nick => context.isCircleConversation,
      SlashCommand.poll => context.canCreatePolls,
      _ => true,
    };
  }

  static SlashCommand? named(String name) {
    for (final command in values) {
      if (command.name == name) {
        return command;
      }
    }
    return null;
  }
}

const shrugText = r'¯\_(ツ)_/¯';
const tableflipText = '(╯°□°)╯︵ ┻━┻';
const unflipText = '┬─┬ノ( º _ ºノ)';

const minRollSides = 2;
const maxRollSides = 1000;
const defaultRollSides = 6;

/// The longest circle nickname, as `circle_members.nickname` allows.
const maxSlashNicknameLength = 32;

/// A `/` followed by the command name being typed, with nothing else in
/// the composer.
final _slashQueryPattern = RegExp(r'^/([a-zA-Z]*)$');

/// The lowercased command name being typed when the composer holds only a
/// `/` and letters, or null otherwise.
String? slashCommandQueryAt(String text) {
  return _slashQueryPattern.firstMatch(text)?.group(1)?.toLowerCase();
}

/// The commands available in [context] whose name starts with [query].
List<SlashCommand> slashCommandCandidates(
  String query,
  SlashCommandContext context,
) {
  final normalized = query.toLowerCase();
  return [
    for (final command in SlashCommand.values)
      if (command.isAvailableIn(context) && command.name.startsWith(normalized))
        command,
  ];
}

/// Backslash-escapes the characters the message markdown treats as
/// markers, so [text] shows exactly as written.
String escapeMarkdown(String text) {
  return text.replaceAllMapped(
    RegExp(r'[\\*_~|`>]'),
    (match) => '\\${match.group(0)}',
  );
}

/// What sending a composer text that starts with a command does.
sealed class SlashCommandAction {
  const SlashCommandAction();
}

/// Sends [body] as an ordinary text message.
final class SlashSendText extends SlashCommandAction {
  const SlashSendText(this.body);

  final String body;
}

/// Opens the poll composer.
final class SlashOpenPoll extends SlashCommandAction {
  const SlashOpenPoll();
}

/// Sets the current user's circle nickname; null resets it.
final class SlashSetNickname extends SlashCommandAction {
  const SlashSetNickname(this.nickname);

  final String? nickname;
}

/// Sets the current user's custom status until changed; both null clears
/// it.
final class SlashSetStatus extends SlashCommandAction {
  const SlashSetStatus({this.emoji, this.text});

  final String? emoji;
  final String? text;

  bool get clears => emoji == null && text == null;
}

/// The command was used wrongly; nothing is sent.
final class SlashCommandError extends SlashCommandAction {
  const SlashCommandError(this.message);

  final String message;
}

/// What sending [input] does when it starts with a command available in
/// [context], or null when it is ordinary text (including unknown and
/// unavailable commands, which are sent as written).
SlashCommandAction? parseSlashCommand(
  String input, {
  required SlashCommandContext context,
  math.Random? random,
}) {
  final text = input.trim();
  final match = RegExp(r'^/([a-zA-Z]+)(?:\s+([\s\S]*))?$').firstMatch(text);
  if (match == null) {
    return null;
  }
  final command = SlashCommand.named(match.group(1)!.toLowerCase());
  if (command == null || !command.isAvailableIn(context)) {
    return null;
  }
  final argument = (match.group(2) ?? '').trim();

  String withSuffix(String suffix) {
    final escaped = escapeMarkdown(suffix);
    return argument.isEmpty ? escaped : '$argument $escaped';
  }

  switch (command) {
    case SlashCommand.shrug:
      return SlashSendText(withSuffix(shrugText));
    case SlashCommand.tableflip:
      return SlashSendText(withSuffix(tableflipText));
    case SlashCommand.unflip:
      return SlashSendText(withSuffix(unflipText));
    case SlashCommand.me:
      if (argument.isEmpty) {
        return const SlashCommandError('Usage: /me <message>');
      }
      return SlashSendText('*$argument*');
    case SlashCommand.spoiler:
      if (argument.isEmpty) {
        return const SlashCommandError('Usage: /spoiler <message>');
      }
      return SlashSendText('||$argument||');
    case SlashCommand.roll:
      final sides = argument.isEmpty
          ? defaultRollSides
          : int.tryParse(argument);
      if (sides == null || sides < minRollSides || sides > maxRollSides) {
        return const SlashCommandError(
          'Choose between $minRollSides and $maxRollSides sides.',
        );
      }
      final rolled = (random ?? math.Random()).nextInt(sides) + 1;
      return SlashSendText('🎲 rolled $rolled (1–$sides)');
    case SlashCommand.poll:
      return const SlashOpenPoll();
    case SlashCommand.nick:
      if (argument.characters.length > maxSlashNicknameLength) {
        return const SlashCommandError(
          'Nicknames can be at most $maxSlashNicknameLength characters.',
        );
      }
      return SlashSetNickname(argument.isEmpty ? null : argument);
    case SlashCommand.status:
      return _parseStatus(argument);
  }
}

SlashCommandAction _parseStatus(String argument) {
  if (argument.isEmpty) {
    return const SlashCommandError('Usage: /status <emoji> <text>');
  }
  if (argument.toLowerCase() == 'clear') {
    return const SlashSetStatus();
  }
  final parts = argument.split(RegExp(r'\s+'));
  final first = parts.first;
  final String? emoji;
  final String text;
  if (_looksLikeEmoji(first)) {
    emoji = first;
    text = argument.substring(first.length).trim();
  } else {
    emoji = null;
    text = argument;
  }
  if (text.characters.length > CustomStatus.maxTextLength) {
    return const SlashCommandError(
      'Status text can be at most ${CustomStatus.maxTextLength} characters.',
    );
  }
  return SlashSetStatus(emoji: emoji, text: text.isEmpty ? null : text);
}

/// A short token without letters, digits or ASCII punctuation, such as an
/// emoji (with its modifiers and joiners).
bool _looksLikeEmoji(String token) {
  if (token.characters.length > 4) {
    return false;
  }
  return !RegExp(
    r'[\p{L}\p{N}\x00-\x7F]',
    unicode: true,
  ).hasMatch(token.replaceAll(RegExp('[‍️]'), ''));
}

/// The commands offered above the composer while one is being typed.
class SlashCommandList extends StatelessWidget {
  const SlashCommandList({
    required this.commands,
    required this.highlightedIndex,
    required this.onSelect,
    required this.maxHeight,
    super.key,
  });

  final List<SlashCommand> commands;

  /// The command Enter or Tab picks, moved with the arrow keys.
  final int highlightedIndex;
  final ValueChanged<SlashCommand> onSelect;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('slash-command-list'),
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (index, command) in commands.indexed)
              ListTile(
                key: ValueKey('slash-command-${command.name}'),
                dense: true,
                selected: index == highlightedIndex,
                selectedTileColor: theme.colorScheme.primary.withValues(
                  alpha: 0.12,
                ),
                leading: const Icon(Icons.keyboard_command_key, size: 18),
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '/${command.name}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (command.arguments.isNotEmpty)
                        TextSpan(
                          text: ' ${command.arguments}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  command.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => onSelect(command),
              ),
          ],
        ),
      ),
    );
  }
}
