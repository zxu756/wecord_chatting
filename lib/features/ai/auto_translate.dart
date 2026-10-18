// "Auto-translate this chat" (roadmap A5). It plugs into the chat page
// through two registries (see "Chat page extension points" in
// docs/design/wecord-design-language.md) and touches no chat page file:
//
//  * [autoTranslateHeaderAction] adds the switch to the header's More menu
//    (header_actions_registrations.dart);
//  * [autoTranslateFooterEntry] puts [AutoTranslationFooter] inside every text
//    bubble (bubble_footer_registrations.dart). That widget exists only while
//    its bubble is built, so it is also what tells [AutoTranslateController]
//    which messages are on screen: only those are ever sent for translation.
//
// Messages that become visible are collected for a moment, then asked for in
// batches of up to 20 per chat; the server answers from its cache first and
// only runs the model for what it has never translated.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/ai/ai_models.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/ai_translation.dart';
import 'package:wecord/features/ai/language_detect.dart';
import 'package:wecord/features/ai/translate_repository.dart';
import 'package:wecord/features/ai/translate_settings.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart'
    show chatConversationSummaryProvider;
import 'package:wecord/features/chats/thread/registry/bubble_footer.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';

/// Messages asked for at most per request: the server's limit.
const autoTranslateBatchSize = 20;

/// How long newly visible messages are collected before they are asked for.
const autoTranslateDelay = Duration(milliseconds: 350);

/// Why auto-translate stopped in a chat, shown once under one message.
@immutable
class AutoTranslateNotice {
  const AutoTranslateNotice({required this.messageId, required this.error});

  /// The message the notice sits under.
  final String messageId;
  final Object error;
}

/// Per chat: the notice for why auto-translate is not working, if any.
final autoTranslateProvider =
    NotifierProvider<AutoTranslateController, Map<String, AutoTranslateNotice>>(
      AutoTranslateController.new,
    );

class _Wanted {
  const _Wanted({
    required this.conversationId,
    required this.text,
    required this.target,
  });

  final String conversationId;
  final String text;
  final AiLanguage target;

  int get hash => text.hashCode;
}

class AutoTranslateController
    extends Notifier<Map<String, AutoTranslateNotice>> {
  /// Visible messages waiting to be asked for.
  final _pending = <String, _Wanted>{};

  /// Messages in a request that is on its way.
  final _inFlight = <String>{};

  /// What was answered (translated or deliberately skipped), by message,
  /// language and text, so a message is asked for once.
  final _settled = <String>{};

  /// The chat of every message asked for, and the messages the person set
  /// back to the original.
  final _chatOf = <String, String>{};
  final _dismissed = <String>{};

  /// Chats auto-translate stopped in (limit, AI off): no more requests until
  /// the person switches it again.
  final _blocked = <String>{};
  final _retries = <String, int>{};
  Timer? _timer;

  /// How long visible messages are collected (tests make it short).
  @visibleForTesting
  Duration delay = autoTranslateDelay;
  var _queue = Future<void>.value();

  @override
  Map<String, AutoTranslateNotice> build() {
    ref.onDispose(() => _timer?.cancel());
    return const {};
  }

  String _key(String messageId, AiLanguage target, int hash) =>
      '$messageId|${target.code}|$hash';

  /// A visible message that [text] should be translated to [target].
  void request({
    required String conversationId,
    required String messageId,
    required String text,
    required AiLanguage target,
  }) {
    final wanted = _Wanted(
      conversationId: conversationId,
      text: text,
      target: target,
    );
    if (_dismissed.contains(messageId) ||
        _blocked.contains(conversationId) ||
        _inFlight.contains(messageId) ||
        _settled.contains(_key(messageId, target, wanted.hash))) {
      return;
    }
    _chatOf[messageId] = conversationId;
    _pending[messageId] = wanted;
    _arm();
  }

  /// The message left the screen before it was asked for.
  void cancel(String messageId) {
    _pending.remove(messageId);
  }

  /// The person set [messageId] back to the original.
  void dismiss(String messageId) {
    _pending.remove(messageId);
    _dismissed.add(messageId);
  }

  /// Auto-translate was switched in [conversationId]: start fresh there.
  void reset(String conversationId) {
    _blocked.remove(conversationId);
    _dismissed.removeWhere((id) => _chatOf[id] == conversationId);
    _settled.clear();
    _retries.clear();
    _pending.removeWhere(
      (_, wanted) => wanted.conversationId == conversationId,
    );
    if (state.containsKey(conversationId)) {
      state = {...state}..remove(conversationId);
    }
  }

  void _arm() {
    _timer ??= Timer(delay, () {
      _timer = null;
      _queue = _queue.then((_) => _flush()).catchError((Object _) {});
    });
  }

  Future<void> _flush() async {
    if (!ref.mounted || _pending.isEmpty) {
      return;
    }
    // One chat and one language at a time.
    final first = _pending.entries.first.value;
    final batch = <String, _Wanted>{};
    for (final entry in _pending.entries) {
      if (batch.length == autoTranslateBatchSize) {
        break;
      }
      if (entry.value.conversationId == first.conversationId &&
          entry.value.target == first.target) {
        batch[entry.key] = entry.value;
      }
    }
    batch.keys.forEach(_pending.remove);
    _inFlight.addAll(batch.keys);
    if (_pending.isNotEmpty) {
      // More are waiting: the next request follows this one.
      _queue = _queue.then((_) => _flush()).catchError((Object _) {});
    }
    try {
      final result = await ref
          .read(translateRepositoryProvider)
          .translateBatch(
            conversationId: first.conversationId,
            messageIds: batch.keys.toList(),
            target: first.target,
          );
      if (!ref.mounted) {
        return;
      }
      _apply(batch, first, result);
    } on Object catch (error) {
      if (!ref.mounted) {
        return;
      }
      _failed(first.conversationId, batch.keys.first, error);
    } finally {
      _inFlight.removeAll(batch.keys);
    }
  }

  void _apply(
    Map<String, _Wanted> batch,
    _Wanted first,
    TranslateBatchResult result,
  ) {
    final translations = ref.read(aiTranslationsProvider.notifier);
    for (final MapEntry(key: id, value: wanted) in batch.entries) {
      final key = _key(id, wanted.target, wanted.hash);
      if (result.translations[id] case final translated?) {
        _settled.add(key);
        if (!_dismissed.contains(id)) {
          translations.showAuto(
            id,
            text: translated.text,
            language: wanted.target,
            sourceHash: wanted.hash,
          );
        }
      } else if (result.skipped[id]?.retryable ?? false) {
        // Left for the next request: ask again, a few times.
        final tries = (_retries[key] ?? 0) + 1;
        _retries[key] = tries;
        if (tries <= 2 && !result.limitReached) {
          _pending.putIfAbsent(id, () => wanted);
          _arm();
        } else if (result.skipped[id] != TranslateSkip.later) {
          _settled.add(key);
        }
      } else {
        _settled.add(key);
      }
    }
    if (result.limitReached) {
      _failed(
        first.conversationId,
        batch.keys.first,
        const AiLimitReachedException(),
      );
    }
  }

  void _failed(String conversationId, String anchorId, Object error) {
    if (error is AiNotConfiguredException) {
      ref.invalidate(aiStatusProvider);
    }
    final stops =
        error is AiNotConfiguredException ||
        error is AiLimitReachedException ||
        error is AiTurnedOffException ||
        error is AiDisabledInCircleException;
    if (!stops) {
      // Offline, busy, a bad answer: the messages are asked for again the
      // next time they come into view.
      return;
    }
    _blocked.add(conversationId);
    _pending.removeWhere(
      (_, wanted) => wanted.conversationId == conversationId,
    );
    state = {
      ...state,
      conversationId: AutoTranslateNotice(messageId: anchorId, error: error),
    };
  }

  /// Takes the notice of [conversationId] away.
  void clearNotice(String conversationId) {
    if (state.containsKey(conversationId)) {
      state = {...state}..remove(conversationId);
    }
  }
}

/// What the bubble footer shows for a message in a chat that has
/// auto-translate on: the translation under the text, with "Show original".
/// It asks for the translation while its bubble is built, which is the only
/// time the message can be on screen.
class AutoTranslationFooter extends ConsumerStatefulWidget {
  const AutoTranslationFooter({
    required this.message,
    required this.color,
    super.key,
  });

  final ChatMessage message;

  /// The color of the message's text, which the translation follows.
  final Color color;

  @override
  ConsumerState<AutoTranslationFooter> createState() =>
      _AutoTranslationFooterState();
}

class _AutoTranslationFooterState extends ConsumerState<AutoTranslationFooter> {
  late final AutoTranslateController _controller;
  String? _requested;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(autoTranslateProvider.notifier);
    final id = widget.message.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(conversationTranslateProvider.notifier).ensureLoaded(id);
      }
    });
  }

  @override
  void dispose() {
    _controller.cancel(widget.message.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final conversationId = message.conversationId;
    final pref = ref.watch(
      conversationTranslateProvider.select((all) => all[conversationId]),
    );
    final settings = ref.watch(aiTranslateSettingsProvider);
    // A circle that turned AI off gets no requests at all (the server refuses
    // them too).
    final circleId = ref.watch(
      chatConversationSummaryProvider(
        conversationId,
      ).select((summary) => summary.value?.circleId),
    );
    final available = ref.watch(aiAvailableProvider(circleId));
    final target = pref?.target ?? translateTargetOf(settings);
    final on = (pref?.auto ?? false) && available;
    final body = message.body;

    final eligible =
        on &&
        message.type == MessageType.text &&
        message.recalledAt == null &&
        message.reviewState == null &&
        worthTranslating(body, target, skipLanguages: settings.noTranslate);
    if (eligible) {
      final key = '${message.id}|${target.code}|${body.hashCode}';
      if (_requested != key) {
        _requested = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _requested == key) {
            _controller.request(
              conversationId: conversationId,
              messageId: message.id,
              text: body,
              target: target,
            );
          }
        });
      }
    } else {
      _requested = null;
    }

    final notice = ref.watch(
      autoTranslateProvider.select((all) => all[conversationId]),
    );
    if (on && notice != null && notice.messageId == message.id) {
      return TranslationCard(
        translation: AiMessageTranslation(
          phase: AiTranslationPhase.failed,
          language: target,
          error: notice.error,
          auto: true,
        ),
        color: widget.color,
        onHide: () => _controller.clearNotice(conversationId),
        onRetry: () {},
      );
    }
    final translation = ref.watch(
      aiTranslationsProvider.select((all) => all[message.id]),
    );
    if (!eligible ||
        translation == null ||
        !translation.auto ||
        translation.sourceHash != body.hashCode ||
        translation.language != target) {
      return const SizedBox.shrink();
    }
    return TranslationCard(
      translation: translation,
      color: widget.color,
      onHide: () => ref.read(aiTranslationsProvider.notifier).hide(message.id),
      onRetry: () {},
    );
  }
}

/// The footer slot's entry. Orders inside the bubble: 100 task chip, 150 this,
/// 200 "edited", 300 "published".
final BubbleFooterEntry autoTranslateFooterEntry = BubbleFooterEntry.inside(
  id: 'auto-translation',
  order: 150,
  build: (ctx) => [
    if (ctx.message.type == MessageType.text &&
        !ctx.isRecalled &&
        !ctx.isCurrentUser)
      AutoTranslationFooter(message: ctx.message, color: ctx.textColor),
  ],
);

/// "Auto-translate this chat" in the header's More menu, after Summarize
/// (1200) and before the parent's own actions (1500).
final HeaderActionContribution autoTranslateHeaderAction =
    HeaderActionContribution(
      id: 'auto-translate',
      order: 1250,
      build: (ctx) {
        if (ctx.isNoteToSelf ||
            !ctx.ref.watch(aiAvailableProvider(ctx.circleId))) {
          return null;
        }
        final conversationId = ctx.conversationId;
        final controller = ctx.ref.read(conversationTranslateProvider.notifier);
        controller.ensureLoaded(conversationId);
        final on = ctx.ref.watch(
          conversationTranslateProvider.select(
            (all) => all[conversationId]?.auto ?? false,
          ),
        );
        return ChatThreadAction(
          id: 'auto-translate',
          tooltip: on
              ? tr('Stop auto-translating')
              : tr('Auto-translate this chat'),
          icon: Icons.translate_rounded,
          selectedIcon: Icons.g_translate_rounded,
          isSelected: on,
          menuOnly: true,
          onPressed: () {
            ctx.ref.read(autoTranslateProvider.notifier).reset(conversationId);
            unawaited(controller.setAuto(conversationId, on: !on));
          },
        );
      },
    );
