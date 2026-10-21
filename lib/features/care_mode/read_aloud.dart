import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/care_mode/care_mode_settings.dart';
import 'package:wecord/features/care_mode/speech_reader.dart';
import 'package:wecord/features/chats/message_action_menu.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/thread/registry/message_actions.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// What gets spoken for a text message: its words, without markdown marks.
/// Empty when there is nothing to say.
String readAloudTextFor(ChatMessage message) {
  if (message.type != MessageType.text || message.recalledAt != null) {
    return '';
  }
  return plainTextFromMarkdown(
    message.body,
  ).replaceAll(RegExp(r'[ \t]*\n[ \t]*'), '. ').trim();
}

/// "Read aloud" in a text message's long-press menu, while Care mode is on
/// and reading aloud wasn't turned off. It sits right after Copy (200).
final readAloudAction = MessageActionContribution(
  id: 'read-aloud',
  order: 250,
  build: (ctx) {
    if (!ctx.container.read(careModeProvider).readsAloud ||
        !ctx.container.read(speechReaderProvider).isSupported) {
      return const [];
    }
    final text = readAloudTextFor(ctx.message);
    if (text.isEmpty || ctx.isPending) {
      return const [];
    }
    return [
      MessageAction(
        key: const ValueKey('message-read-aloud'),
        icon: Icons.volume_up_rounded,
        label: tr('Read aloud'),
        onSelected: () => unawaited(readAloud(ctx.context, text)),
      ),
    ];
  },
);

/// Reads [text] out loud and shows "Reading aloud" with a Stop button until
/// it ends. A device that cannot read says so instead.
Future<void> readAloud(BuildContext context, String text) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final reader = container.read(speechReaderProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await reader.speak(
      text,
      language: speechLanguageFor(text, appIsChinese: AppStrings.isChinese),
    );
  } on SpeechReaderException {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(tr("This device can't read aloud."))),
      );
    return;
  }
  if (messenger == null) {
    return;
  }
  messenger.hideCurrentSnackBar();
  final bar = messenger.showSnackBar(
    SnackBar(
      key: const ValueKey('reading-aloud-bar'),
      content: Text(tr('Reading aloud')),
      duration: const Duration(minutes: 10),
      action: SnackBarAction(
        label: tr('Stop'),
        onPressed: () => unawaited(reader.stop()),
      ),
    ),
  );
  void closeWhenDone() {
    if (!reader.speaking.value) {
      reader.speaking.removeListener(closeWhenDone);
      bar.close();
    }
  }

  reader.speaking.addListener(closeWhenDone);
  // It may have ended while the bar was being made.
  closeWhenDone();
}
