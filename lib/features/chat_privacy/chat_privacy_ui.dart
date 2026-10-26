import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_notice.dart';
import 'package:wecord/features/chat_privacy/chat_privacy_repository.dart';
import 'package:wecord/features/chats/chat_thread_controller.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/screen_capture/screen_capture_status.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Advanced chat privacy" in the header's More menu of a direct chat or a
/// group, after Lock chat (1300).
final HeaderActionContribution chatPrivacyHeaderAction =
    HeaderActionContribution(
      id: 'chat-privacy',
      order: 1350,
      build: (ctx) {
        if (ctx.isNoteToSelf || !ctx.isDirectOrGroup) {
          return null;
        }
        final restricted = ctx.ref.watch(
          restrictSharingProvider(ctx.conversationId),
        );
        return ChatThreadAction(
          id: 'chat-privacy',
          tooltip: tr('Advanced chat privacy'),
          icon: Icons.shield_outlined,
          selectedIcon: Icons.shield_rounded,
          isSelected: restricted,
          menuOnly: true,
          onPressed: () => unawaited(
            showChatPrivacySheet(
              ctx.context,
              conversationId: ctx.conversationId,
              isGroup: ctx.isGroup,
              canChange:
                  ctx.isDirect || ctx.groupDetail?.canManageGroup == true,
            ),
          ),
        );
      },
    );

/// The bar under the chat's header while the chat is restricted. It says what
/// is off, and that screenshots are not among the things it can stop. It also
/// keeps the setting current: a notice about it arriving in the chat (from the
/// other person, or an admin on another device) reads it again.
class ChatPrivacyBanner extends ConsumerWidget {
  const ChatPrivacyBanner({
    required this.conversationId,
    required this.isGroup,
    required this.canChange,
    super.key,
  });

  final String conversationId;
  final bool isGroup;
  final bool canChange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(
      chatThreadProvider(
        conversationId,
      ).select((thread) => latestPrivacyNoticeId(thread.value?.messages)),
      (previous, next) {
        if (previous != next) {
          ref.invalidate(chatPrivacyProvider(conversationId));
        }
      },
    );
    if (!ref.watch(restrictSharingProvider(conversationId))) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: WeCordPressable(
        key: const ValueKey('chat-privacy-banner'),
        onPressed: () => unawaited(
          showChatPrivacySheet(
            context,
            conversationId: conversationId,
            isGroup: isGroup,
            canChange: canChange,
          ),
        ),
        semanticLabel: tr('Advanced chat privacy is on'),
        hint: tr('Opens the details'),
        pressedScale: 0.99,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        builder: (context, states) => Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.shield_rounded, size: 17, color: c.ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Advanced chat privacy is on'),
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(
                        'Forwarding, saving, copying and AI are off here. It cannot stop screenshots.',
                      ),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the chat's advanced chat privacy: the switch and what it does.
Future<void> showChatPrivacySheet(
  BuildContext context, {
  required String conversationId,
  required bool isGroup,
  required bool canChange,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Advanced chat privacy'),
    builder: (context, _) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: ChatPrivacySheetBody(
        conversationId: conversationId,
        isGroup: isGroup,
        canChange: canChange,
      ),
    ),
  );
}

/// The sheet's content.
class ChatPrivacySheetBody extends ConsumerStatefulWidget {
  const ChatPrivacySheetBody({
    required this.conversationId,
    required this.isGroup,
    required this.canChange,
    super.key,
  });

  final String conversationId;
  final bool isGroup;

  /// In a group only an owner or admin can change it.
  final bool canChange;

  @override
  ConsumerState<ChatPrivacySheetBody> createState() =>
      _ChatPrivacySheetBodyState();
}

class _ChatPrivacySheetBodyState extends ConsumerState<ChatPrivacySheetBody> {
  var _busy = false;

  Future<void> _set(bool enabled) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(chatPrivacyRepositoryProvider)
          .set(widget.conversationId, enabled);
      ref.invalidate(chatPrivacyProvider(widget.conversationId));
    } on Object {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr('Could not change it. Check your connection and try again.'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final privacy =
        ref.watch(chatPrivacyProvider(widget.conversationId)).value ??
        ChatPrivacy.open;
    final me = ref.watch(authStateProvider).value?.id;
    // A direct chat has a switch for each person; the chat stays restricted
    // while either has asked. A group has one, for its admins.
    final on = widget.isGroup
        ? privacy.restricted
        : privacy.requestedByUser(me);
    final partnerHolds = !widget.isGroup && privacy.onlyOthersAsked(me);
    final partnerAlsoAsked =
        !widget.isGroup && on && privacy.requestedBy.length > 1;
    final footer = widget.isGroup
        ? (widget.canChange
              ? tr('Group owners and admins can turn this on or off.')
              : tr('Only group owners and admins can change this.'))
        : partnerHolds
        ? tr(
            'The other person turned this on. It stays on until they turn it off.',
          )
        : partnerAlsoAsked
        ? tr(
            'You both turned this on. It stays on until you have both turned it off.',
          )
        : tr(
            'Either of you can turn this on. It stays on until you have both turned it off.',
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          footer: footer,
          children: [
            SettingsRow.toggle(
              key: const ValueKey('chat-privacy-toggle'),
              icon: Icons.shield_outlined,
              tone: privacy.restricted
                  ? SettingsTone.success
                  : SettingsTone.neutral,
              title: tr('Restrict sharing in this chat'),
              subtitle: privacy.restricted
                  ? tr('Sharing is restricted')
                  : tr('Anyone here can forward, save or copy messages'),
              value: on,
              onChanged: (_busy || !widget.canChange)
                  ? null
                  : (value) => unawaited(_set(value)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const ChatPrivacyExplainer(),
      ],
    );
  }
}

/// What advanced chat privacy does and, as plainly, what it cannot do. Used
/// by the chat's sheet and by Settings.
class ChatPrivacyExplainer extends StatelessWidget {
  const ChatPrivacyExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.muted,
          ),
        ),
      ),
    );
    return Column(
      key: const ValueKey('chat-privacy-explainer'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(tr('What this does')),
        _Point(
          icon: Icons.forward_to_inbox_outlined,
          text: tr(
            'Messages cannot be forwarded, merged into a forward or saved for later, and nobody can save them to a group album or group files.',
          ),
        ),
        _Point(
          icon: Icons.copy_all_outlined,
          text: tr(
            'Copying, translating, reading by AI and saving pictures and files to your device are off.',
          ),
        ),
        _Point(
          icon: Icons.archive_outlined,
          text: tr(
            'A data export leaves this chat\'s words and files out. The server refuses these, not just the app.',
          ),
        ),
        const SizedBox(height: 12),
        heading(tr('What it cannot do')),
        _Point(
          icon: Icons.screenshot_outlined,
          warning: true,
          text: tr(
            'It cannot stop screenshots, screen recordings, a photo of the screen, or someone typing a message out again. Anyone who can read a message can keep a copy this way.',
          ),
        ),
        _Point(
          icon: Icons.visibility_outlined,
          warning: true,
          text: tr(
            'Messages sent before it was turned on were already shared. Things already saved or forwarded stay where they are.',
          ),
        ),
        const SizedBox(height: 12),
        const ScreenCaptureStatusCard(),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, this.warning = false});

  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: 18,
              color: warning ? c.warningText : c.muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, height: 1.45, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings → Privacy & Safety → "Advanced chat privacy".
class ChatPrivacySettingsRow extends StatelessWidget {
  const ChatPrivacySettingsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsRow(
      key: const ValueKey('chat-privacy-tile'),
      icon: Icons.shield_outlined,
      title: tr('Advanced chat privacy'),
      subtitle: tr(
        'Stop forwarding, saving and AI in a chat, and screenshot alerts',
      ),
      showChevron: true,
      onTap: () => openChatPrivacySettings(context),
    );
  }
}

void openChatPrivacySettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const ChatPrivacyScreen()),
  );
}

/// What advanced chat privacy and screenshot alerts are, and what this device
/// can do about them.
class ChatPrivacyScreen extends StatelessWidget {
  const ChatPrivacyScreen({super.key});

  static const screenKey = ValueKey('chat-privacy-screen');

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SettingsPage(
      key: screenKey,
      title: tr('Advanced chat privacy'),
      children: [
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            tr(
              'Open a chat, choose More, then Advanced chat privacy. In a direct chat either of you can turn it on; in a group an owner or admin does.',
            ),
            style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
          ),
        ),
        const SizedBox(height: 16),
        const ChatPrivacyExplainer(),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            screenCaptureSenderNote(),
            style: TextStyle(fontSize: 13.5, height: 1.45, color: c.muted),
          ),
        ),
      ],
    );
  }
}
