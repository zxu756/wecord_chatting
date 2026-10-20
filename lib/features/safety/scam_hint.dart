import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart'
    show chatConversationSummaryProvider;
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/contacts/contacts_screen.dart'
    show friendsProvider;
import 'package:wecord/features/reports/report_message_sheet.dart';
import 'package:wecord/features/safety/scam_rules.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Where the people whose warnings were hidden are kept; tests swap in
/// memory.
abstract interface class ScamHintStore {
  Future<Set<String>> load();

  Future<void> save(Set<String> senderIds);
}

const _dismissedKey = 'wecord.scam_hint.dismissed';

/// The most senders remembered; the oldest go first.
const maxDismissedSenders = 200;

class SharedPreferencesScamHintStore implements ScamHintStore {
  const SharedPreferencesScamHintStore();

  @override
  Future<Set<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_dismissedKey) ?? const <String>[])
        .toSet();
  }

  @override
  Future<void> save(Set<String> senderIds) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_dismissedKey, senderIds.toList());
  }
}

class InMemoryScamHintStore implements ScamHintStore {
  InMemoryScamHintStore([Set<String> initial = const {}]) : _ids = {...initial};

  Set<String> _ids;

  @override
  Future<Set<String>> load() async => _ids;

  @override
  Future<void> save(Set<String> senderIds) async => _ids = {...senderIds};
}

final scamHintStoreProvider = Provider<ScamHintStore>(
  (ref) => const SharedPreferencesScamHintStore(),
);

/// The senders whose scam hints were hidden ("I know this person", or a
/// report was sent), kept on this device. Hiding is per person, not per
/// message, so a stranger's burst of messages is not a burst of warnings.
final scamHintDismissedProvider =
    NotifierProvider<ScamHintDismissed, Set<String>>(ScamHintDismissed.new);

class ScamHintDismissed extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    unawaited(
      ref
          .read(scamHintStoreProvider)
          .load()
          .then((saved) {
            // Hiding done while loading is not lost.
            state = {...saved, ...state};
          })
          .catchError((Object _) {}),
    );
    return const {};
  }

  void dismiss(String senderId) {
    final next = {...state, senderId};
    while (next.length > maxDismissedSenders) {
      next.remove(next.first);
    }
    state = next;
    unawaited(
      ref.read(scamHintStoreProvider).save(next).catchError((Object _) {}),
    );
  }
}

/// What the hint says about [signal] (under the line that says they are not a
/// friend).
String scamHintDetail(ScamSignal signal) => switch (signal) {
  ScamSignal.payment => tr(
    "They're asking about a payment or transfer. Never pay someone you can't verify.",
  ),
  ScamSignal.code => tr(
    "They're asking for a verification code. Never share one.",
  ),
  ScamSignal.prize => tr(
    'Prizes and giveaways from strangers are usually scams.',
  ),
  ScamSignal.investment => tr('Promises of easy returns are a common scam.'),
  ScamSignal.giftCard => tr('Nobody legitimate asks to be paid in gift cards.'),
  ScamSignal.impersonation => tr(
    "Real support teams don't ask for passwords or codes in chat.",
  ),
  ScamSignal.link => tr('This link looks suspicious. Check it before you tap.'),
};

/// Whether the hint applies to [message] as far as the message alone says:
/// someone else's, readable text that isn't from a bot or the AI, not held by
/// the AI guard (that already got a look), and with something in it the rules
/// notice. The rest (a group or circle, not a friend) needs the providers.
ScamSignal? scamSignalFor(ChatMessage message, {required bool isOwn}) {
  if (isOwn ||
      message.type != MessageType.text ||
      message.recalledAt != null ||
      message.webhookId != null ||
      message.aiReply != null ||
      message.reviewState != null) {
    return null;
  }
  return detectScamSignal(message.body);
}

/// The yellow line under a stranger's message: "Watch out for scams: they
/// aren't your friend", with what to be careful about, Report and a way to
/// hide it for that person. Only a hint: nothing is blocked.
class ScamHintStrip extends ConsumerWidget {
  const ScamHintStrip({required this.message, required this.signal, super.key});

  final ChatMessage message;
  final ScamSignal signal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(scamHintDismissedProvider).contains(message.senderId)) {
      return const SizedBox.shrink();
    }
    final summary = ref
        .watch(chatConversationSummaryProvider(message.conversationId))
        .value;
    // Direct chats are friends only, and the file helper is yours alone.
    if (summary == null ||
        summary.type == ConversationType.direct ||
        summary.isNoteToSelf) {
      return const SizedBox.shrink();
    }
    final friends = ref.watch(friendsProvider).value;
    if (friends == null || friends.any((p) => p.id == message.senderId)) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final title = tr("Watch out for scams: they aren't your friend");
    final detail = scamHintDetail(signal);
    return Container(
      key: const ValueKey('scam-hint'),
      padding: const EdgeInsets.fromLTRB(10, 8, 2, 4),
      decoration: BoxDecoration(
        color: c.warningSoft,
        borderRadius: BorderRadius.circular(WeCordRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: ExcludeSemantics(
              child: Icon(
                Icons.warning_amber_rounded,
                size: 18,
                color: c.warningText,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  container: true,
                  label: '$title. $detail',
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: c.warningText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: tr('Report this message'),
                  child: ExcludeSemantics(
                    child: InkWell(
                      key: const ValueKey('scam-hint-report'),
                      borderRadius: BorderRadius.circular(WeCordRadii.xs),
                      onTap: () =>
                          unawaited(_report(context, ref, summary.circleId)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.flag_outlined,
                              size: 15,
                              color: c.warningText,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                tr('Report this message'),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: c.warningText,
                                  decoration: TextDecoration.underline,
                                  decorationColor: c.warningText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const ValueKey('scam-hint-dismiss'),
            tooltip: tr('Hide warnings for this person'),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            color: c.muted,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => ref
                .read(scamHintDismissedProvider.notifier)
                .dismiss(message.senderId),
          ),
        ],
      ),
    );
  }

  Future<void> _report(
    BuildContext context,
    WidgetRef ref,
    String? circleId,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final sent = await showReportMessageSheet(
      context,
      message: message,
      senderName: _senderName(message),
      circleId: circleId,
    );
    if (sent != true) {
      return;
    }
    // The report is in; no need to warn about this person again.
    ref.read(scamHintDismissedProvider.notifier).dismiss(message.senderId);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            tr('Report sent. Thank you for helping keep WeCord safe.'),
          ),
        ),
      );
  }
}

String _senderName(ChatMessage message) {
  final nickname = message.senderNickname?.trim() ?? '';
  if (nickname.isNotEmpty) {
    return nickname;
  }
  return message.sender?.displayLabel ?? tr('the sender');
}

/// The footer slot's entry, under the bubble between the link preview (100)
/// and the thread chip (200).
final BubbleFooterEntry scamHintFooterEntry = BubbleFooterEntry.below(
  id: 'scam-hint',
  order: 150,
  cardGap: 6,
  cardMaxWidth: 440,
  build: (ctx) {
    final signal = scamSignalFor(ctx.message, isOwn: ctx.isCurrentUser);
    if (signal == null) {
      return null;
    }
    return ScamHintStrip(message: ctx.message, signal: signal);
  },
);
