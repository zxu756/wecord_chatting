import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/chats/events/chat_event_format.dart';
import 'package:wecord/features/chats/events/chat_events_repository.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/events2/event_widgets.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/shared/calendar/calendar_file_saver.dart';
import 'package:wecord/shared/calendar/ics.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/models/event_extras.dart';

/// A chat's events, soonest first, past and cancelled ones too. Reloads
/// when an event or an answer changes.
final chatEventsProvider = FutureProvider.autoDispose
    .family<List<ChatEvent>, String>((ref, conversationId) async {
      final repository = ref.watch(chatEventsRepositoryProvider);
      Timer? debounce;
      final subscription = repository.changes(conversationId).listen((_) {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 300), ref.invalidateSelf);
      });
      ref.onDispose(() {
        debounce?.cancel();
        subscription.cancel();
      });
      return repository.listEvents(conversationId, includePast: true);
    });

/// The event pinned to the chat header, if it is still on or ahead.
ChatEvent? pinnedChatEvent(List<ChatEvent> events, DateTime now) {
  for (final event in events) {
    if (event.isPinned && event.statusAt(now) != ChatEventStatus.over) {
      if (!event.isCancelled) {
        return event;
      }
    }
  }
  return null;
}

/// The event with [eventId] from the chat's list.
ChatEvent? chatEventById(List<ChatEvent>? events, String eventId) {
  if (events == null) {
    return null;
  }
  for (final event in events) {
    if (event.id == eventId) {
      return event;
    }
  }
  return null;
}

/// The signed-in person's reminders for events about to start.
final chatEventRemindersProvider =
    FutureProvider.autoDispose<List<ChatEventReminder>>((ref) {
      return ref.watch(chatEventsRepositoryProvider).listReminders();
    });

/// What people can do with an event, with the errors turned into
/// messages.
class ChatEventActions {
  ChatEventActions(this.ref, this.context);

  final WidgetRef ref;
  final BuildContext context;

  ChatEventsRepository get _repository =>
      ref.read(chatEventsRepositoryProvider);

  void _refresh(ChatEvent event) =>
      ref.invalidate(chatEventsProvider(event.conversationId));

  void _say(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Sets the caller's answer; tapping the current one clears it (tapping
  /// Going on the waiting list leaves it). Going to an event with questions
  /// asks them first.
  Future<bool> rsvp(ChatEvent event, ChatEventRsvp status) async {
    final extras = event.extras;
    final leaving =
        event.myStatus == status ||
        (status == ChatEventRsvp.going && extras.myWaitlisted);
    final next = leaving ? null : status;
    Map<String, String>? answers;
    if (next == ChatEventRsvp.going && extras.hasQuestions) {
      answers = await showEventAnswerSheet(
        context,
        eventTitle: event.title,
        questions: extras.questions,
        initial: extras.myAnswers,
        actionLabel: extras.isFull(event.goingCount)
            ? tr('Join waiting list')
            : tr('Sign up'),
      );
      if (answers == null) {
        return false;
      }
    }
    try {
      if (answers != null) {
        await ref
            .read(events2RepositoryProvider)
            .rsvpChat(event.id, next?.value, answers: answers);
      } else {
        await _repository.rsvp(event.id, next);
      }
      _refresh(event);
      return true;
    } on EventException catch (error) {
      _say(error.failure.message);
      return false;
    } catch (_) {
      _say(tr('Could not save your answer. Try again.'));
      return false;
    }
  }

  Future<bool> setPinned(ChatEvent event, bool pinned) async {
    try {
      await _repository.setPinned(event.id, pinned: pinned);
      _refresh(event);
      _say(
        pinned
            ? tr('Pinned to the top of the chat.')
            : tr('Unpinned from the chat.'),
      );
      return true;
    } catch (_) {
      _say(tr('Could not change the pin. Try again.'));
      return false;
    }
  }

  Future<bool> cancel(ChatEvent event, {bool wholeSeries = false}) async {
    try {
      if (wholeSeries) {
        await ref
            .read(events2RepositoryProvider)
            .cancelSeries(EventKind.chat, event.id);
      } else {
        await _repository.cancelEvent(event.id);
      }
      _refresh(event);
      return true;
    } catch (_) {
      _say(tr('Could not cancel the event. Try again.'));
      return false;
    }
  }

  /// Offers the event as a calendar file.
  Future<void> addToCalendar(ChatEvent event) async {
    final result = await ref
        .read(calendarFileSaverProvider)
        .save(
          fileName: calendarFileName(event.title),
          contents: chatEventCalendarFile(event, now: DateTime.now()),
        );
    _say(switch (result) {
      CalendarSaveResult.downloaded => tr(
        'Calendar file downloaded. Open it to add the event.',
      ),
      CalendarSaveResult.shared => tr('Choose Calendar to add the event.'),
      CalendarSaveResult.failed => tr('Could not create the calendar file.'),
    });
  }

  /// Opens the event's link.
  Future<void> openLink(ChatEvent event) async {
    final uri = Uri.tryParse(event.linkUrl ?? '');
    if (uri == null) {
      return;
    }
    try {
      await ref.read(linkLauncherProvider)(context, uri);
    } catch (_) {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      ).catchError((Object _) => false);
    }
  }
}
