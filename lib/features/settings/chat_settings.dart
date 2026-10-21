import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chat_folders/chat_folders_screen.dart';
import 'package:wecord/features/chats/chat_polish/chat_polish_settings.dart';
import 'package:wecord/features/chats/quick_replies/quick_replies_screen.dart';
import 'package:wecord/features/groups/group_cleanup.dart';
import 'package:wecord/features/stickers/sticker_management_screen.dart';
import 'package:wecord/features/storage/storage_screen.dart';
import 'package:wecord/features/voice_input/voice_input_settings.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Settings -> Chats: voice input and housekeeping for your conversations.
class ChatSettingsGroup extends ConsumerWidget {
  const ChatSettingsGroup({this.header, super.key});

  final String? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsGroup(
      header: header,
      children: [
        // Speak to type: only where the device or the browser can do it.
        if (ref.watch(voiceInputSupportedProvider))
          SettingsRow.toggle(
            key: const ValueKey('voice-input-switch'),
            icon: Icons.graphic_eq_rounded,
            tone: SettingsTone.accent,
            title: tr('Show voice input'),
            subtitle: tr(
              'Speak to type in the message box and edit the words before sending. This is not a voice message.',
            ),
            value: ref.watch(showVoiceInputProvider),
            onChanged: (value) =>
                unawaited(ref.read(showVoiceInputProvider.notifier).set(value)),
          ),
        SettingsRow.toggle(
          key: const ValueKey('voice-autoplay-switch'),
          icon: Icons.queue_music_rounded,
          title: tr('Play voice messages one after another'),
          subtitle: tr(
            'When one ends, the next voice message you have not heard starts.',
          ),
          value: ref.watch(voiceAutoplayProvider),
          onChanged: (value) =>
              unawaited(ref.read(voiceAutoplayProvider.notifier).set(value)),
        ),
        SettingsRow.toggle(
          key: const ValueKey('keyword-effects-switch'),
          icon: Icons.celebration_outlined,
          title: tr('Keyword effects'),
          subtitle: tr(
            'Confetti and other effects when a message holds a wish like "Happy birthday". They are off when animations are reduced.',
          ),
          value: ref.watch(keywordEffectsProvider),
          onChanged: (value) =>
              unawaited(ref.read(keywordEffectsProvider.notifier).set(value)),
        ),
        SettingsRow(
          key: const ValueKey('chat-folders-tile'),
          icon: Icons.folder_copy_outlined,
          tone: SettingsTone.accent,
          title: tr('Chat folders'),
          subtitle: tr('Sort your chats, and fold the groups you rarely read'),
          onTap: () => openChatFolders(context),
        ),
        SettingsRow(
          key: const ValueKey('my-stickers-tile'),
          icon: Icons.add_reaction_outlined,
          title: tr('My stickers'),
          subtitle: tr(
            'Pictures, GIFs and cut-outs you keep to send in any chat',
          ),
          onTap: () => openStickerManagement(context),
        ),
        SettingsRow(
          key: const ValueKey('group-cleanup-tile'),
          icon: Icons.cleaning_services_outlined,
          title: tr('Clean up groups'),
          subtitle: tr('Leave group chats nobody writes in any more'),
          onTap: () => openGroupCleanup(context),
        ),
        SettingsRow(
          key: const ValueKey('quick-replies-tile'),
          icon: Icons.bolt_outlined,
          tone: SettingsTone.accent,
          title: tr('Quick replies'),
          subtitle: tr(
            'Phrases to send with a slash, and an auto-reply for when you are away',
          ),
          onTap: () => openQuickReplies(context),
        ),
        const StorageSettingsRow(),
      ],
    );
  }
}
