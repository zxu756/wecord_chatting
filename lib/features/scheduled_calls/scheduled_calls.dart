// Scheduled calls (roadmap E2): an event of a chat can carry a call.
//
// "Thursday 8 pm, voice meeting": the organiser switches "Attach a call" on in
// the event form (or starts from the chat's "Schedule a call" action). The
// event then holds a call link to its own chat (migrations 202610280100 to
// 202610280140), and the places events already show up carry it along: the
// card in the chat, the details sheet, the pinned strip, the events list, the
// reminder push, My agenda and the calendar subscription. Repeating events
// (C10) hand the call on to their next occurrence by themselves.
//
// The people who can join are the people who can call in the chat anyway; the
// link grants nothing by itself.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/events/chat_event_editor_sheet.dart';
import 'package:wecord/features/chats/events/chat_events_providers.dart';
import 'package:wecord/features/chats/thread/registry/header_actions.dart';
import 'package:wecord/features/voice/voice_session.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';

/// Where an event's call stands at a given time.
enum ScheduledCallPhase {
  /// The event has no call, or was cancelled.
  none,

  /// Not yet: the call opens [ScheduledCall.joinLead] before the start.
  later,

  /// Within [ScheduledCall.joinLead] before the start.
  opening,

  /// The event is on.
  live,

  /// The event is over.
  over,
}

/// The rules of when an event's call can be joined from the app.
abstract final class ScheduledCall {
  /// How long before the start the card offers "Join". The reminder at 15
  /// minutes opens the call, so it has to be open by then.
  static const joinLead = Duration(minutes: 15);

  static ScheduledCallPhase phaseAt(ChatEvent event, DateTime now) {
    if (!event.extras.hasCall || event.isCancelled) {
      return ScheduledCallPhase.none;
    }
    if (!now.isBefore(event.effectiveEndsAt)) {
      return ScheduledCallPhase.over;
    }
    if (!now.isBefore(event.startsAt)) {
      return ScheduledCallPhase.live;
    }
    if (!now.isBefore(event.startsAt.subtract(joinLead))) {
      return ScheduledCallPhase.opening;
    }
    return ScheduledCallPhase.later;
  }

  /// Whether "Join" is on offer: the call is open and not over.
  static bool canJoin(ChatEvent event, DateTime now) {
    final phase = phaseAt(event, now);
    return phase == ScheduledCallPhase.opening ||
        phase == ScheduledCallPhase.live;
  }

  /// The wording of the join button: "In progress · Join" while the event is
  /// on, "Join the call" in the minutes before.
  static String joinLabel(ScheduledCallPhase phase) =>
      phase == ScheduledCallPhase.live
      ? tr('In progress · Join')
      : tr('Join the call');
}

/// Joins the call of [event] (the call going on in its chat, or a new one).
/// Returns whether the person ends up in it; says why when not.
Future<bool> joinScheduledCall(
  BuildContext context,
  WidgetRef ref,
  ChatEvent event,
) {
  return startDirectCall(
    context,
    ref,
    conversationId: event.conversationId,
    name: event.title,
  );
}

/// Whether the current user is in the call of [conversationId] right now.
bool inCallOf(VoiceSession? session, String conversationId) {
  return session != null &&
      session.isDirectCall &&
      session.conversationId == conversationId;
}

/// "Schedule a call" in the chat's More menu: opens the event form with a call
/// attached. For direct chats and groups.
final scheduleCallHeaderAction = HeaderActionContribution(
  id: 'schedule-call',
  order: 2010,
  build: (ctx) => ctx.canCall && ctx.canSend
      ? ChatThreadAction(
          id: 'schedule-call',
          tooltip: tr('Schedule a call'),
          icon: Icons.phone_callback_outlined,
          menuOnly: true,
          onPressed: () => unawaited(_schedule(ctx)),
        )
      : null,
);

Future<void> _schedule(HeaderActionContext ctx) async {
  final created = await showChatEventEditor(
    ctx.context,
    conversationId: ctx.conversationId,
    scheduleCall: true,
  );
  if (created != null && ctx.context.mounted) {
    ctx.ref.invalidate(chatEventsProvider(ctx.conversationId));
  }
}
