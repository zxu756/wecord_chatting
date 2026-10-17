import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/events/chat_event_editor_sheet.dart';
import 'package:wecord/features/chats/events/chat_event_format.dart';
import 'package:wecord/features/chats/events/chat_events_providers.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/time_tokens/time_token_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/chat_event.dart';
import 'package:wecord/shared/ui/ui.dart';

const _englishMonthAbbreviations = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

String _monthLabel(DateTime time) => AppStrings.isChinese
    ? '${time.month}月'
    : _englishMonthAbbreviations[time.month - 1];

/// The event's day as a small calendar page: month over day number.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.time, required this.muted, this.size = 52});

  final DateTime time;
  final bool muted;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final fill = muted ? c.raised : c.accentSoft;
    final ink = muted ? c.muted : c.accentText;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: ShapeDecoration(
          color: fill,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _monthLabel(time),
              style: TextStyle(
                fontSize: size * 0.2,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: ink,
                height: 1.1,
              ),
            ),
            Text(
              '${time.day}',
              style: TextStyle(
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: ink,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Starts in 2 hours", "Live now", "Ended" or "Cancelled" as a small pill.
class ChatEventStatusPill extends StatelessWidget {
  const ChatEventStatusPill({
    required this.event,
    required this.now,
    super.key,
  });

  final ChatEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final status = event.statusAt(now);
    final (fill, ink) = switch (status) {
      ChatEventStatus.live => (c.successSoft, c.successText),
      ChatEventStatus.cancelled => (c.dangerSoft, c.dangerText),
      ChatEventStatus.over => (c.raised, c.muted),
      ChatEventStatus.upcoming => (c.accentSoft, c.accentText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Text(
        chatEventStatusText(event, now),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
      ),
    );
  }
}

/// Going / Maybe / Can't, with the caller's answer lit.
class ChatEventRsvpBar extends ConsumerStatefulWidget {
  const ChatEventRsvpBar({required this.event, super.key});

  final ChatEvent event;

  @override
  ConsumerState<ChatEventRsvpBar> createState() => _ChatEventRsvpBarState();
}

class _ChatEventRsvpBarState extends ConsumerState<ChatEventRsvpBar> {
  ChatEventRsvp? _busy;

  Future<void> _answer(ChatEventRsvp status) async {
    if (_busy != null) {
      return;
    }
    WeCordHaptics.selection();
    setState(() => _busy = status);
    await ChatEventActions(ref, context).rsvp(widget.event, status);
    if (mounted) {
      setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final enabled = !event.isCancelled;
    Widget button(
      ChatEventRsvp status,
      String label,
      IconData icon,
      int count,
    ) {
      return Expanded(
        child: _RsvpButton(
          key: ValueKey('chat-event-rsvp-${status.value}'),
          status: status,
          label: label,
          icon: icon,
          selected: (_busy ?? event.myStatus) == status,
          onPressed: enabled ? () => _answer(status) : null,
        ),
      );
    }

    return Row(
      children: [
        button(
          ChatEventRsvp.going,
          tr('Going'),
          Icons.check_rounded,
          event.goingCount,
        ),
        const SizedBox(width: 8),
        button(
          ChatEventRsvp.maybe,
          tr('Maybe'),
          Icons.help_outline_rounded,
          event.maybeCount,
        ),
        const SizedBox(width: 8),
        button(
          ChatEventRsvp.declined,
          tr("Can't"),
          Icons.close_rounded,
          event.declinedCount,
        ),
      ],
    );
  }
}

class _RsvpButton extends StatelessWidget {
  const _RsvpButton({
    required this.status,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final ChatEventRsvp status;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final (selectedFill, selectedInk) = switch (status) {
      ChatEventRsvp.going => (c.success, Colors.white),
      ChatEventRsvp.maybe => (c.warningSoft, c.warningText),
      ChatEventRsvp.declined => (c.dangerSoft, c.dangerText),
    };
    return WeCordPressable(
      selected: selected,
      toggled: selected,
      semanticLabel: label,
      onPressed: onPressed,
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        final fill = selected
            ? selectedFill
            : hovered
            ? c.raisedStrong
            : c.raised;
        final ink = selected ? selectedInk : c.ink;
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          curve: WeCordMotion.standard,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(WeCordRadii.pill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ExcludeSemantics(child: Icon(icon, size: 16, color: ink)),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Overlapping avatars of the people who are Going or Maybe, then how many.
class ChatEventAttendees extends StatelessWidget {
  const ChatEventAttendees({
    required this.event,
    this.avatarSize = 26,
    super.key,
  });

  final ChatEvent event;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final shown = event.attendees.take(5).toList();
    final overlap = avatarSize * 0.3;
    return Row(
      children: [
        if (shown.isNotEmpty)
          ExcludeSemantics(
            child: SizedBox(
              width: avatarSize + (shown.length - 1) * (avatarSize - overlap),
              height: avatarSize,
              child: Stack(
                children: [
                  for (final (index, person) in shown.indexed)
                    Positioned(
                      left: index * (avatarSize - overlap),
                      child: ChatAvatar(
                        key: ValueKey('chat-event-attendee-${person.id}'),
                        name: person.name,
                        avatarUrl: person.avatarUrl,
                        size: avatarSize,
                        ringColor: c.well,
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (shown.isNotEmpty) const SizedBox(width: 10),
        Expanded(
          child: Text(
            chatEventCountsText(event),
            key: const ValueKey('chat-event-counts'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// An event announced in the chat: its day, title, time, place, who is
/// coming and the Going / Maybe / Can't buttons.
class ChatEventCard extends ConsumerWidget {
  const ChatEventCard({
    required this.conversationId,
    required this.eventId,
    this.fallbackTitle,
    super.key,
  });

  final String conversationId;
  final String eventId;

  /// What the announcement says, until the event itself has loaded.
  final String? fallbackTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final events = ref.watch(chatEventsProvider(conversationId));
    final event = chatEventById(events.value, eventId);
    final now = ref.watch(timeTokenClockProvider).value ?? DateTime.now();
    final desktop = MediaQuery.sizeOf(context).width >= 840;

    Widget card;
    if (event == null) {
      card = _CardFrame(
        child: Row(
          children: [
            Icon(Icons.event_rounded, color: c.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                events.isLoading
                    ? (fallbackTitle ?? tr('Event'))
                    : tr('This event is no longer available.'),
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      card = _EventCardBody(event: event, now: now);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(desktop ? 40 : 16, 6, desktop ? 40 : 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: card,
        ),
      ),
    );
  }
}

class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
        border: Border.all(color: c.lineSoft),
      ),
      child: child,
    );
  }
}

class _EventCardBody extends ConsumerWidget {
  const _EventCardBody({required this.event, required this.now});

  final ChatEvent event;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final status = event.statusAt(now);
    final dimmed =
        status == ChatEventStatus.cancelled || status == ChatEventStatus.over;
    final when = formatChatEventWhen(event, now, use24Hour: use24Hour);
    final description = event.description;
    final summary = [
      tr('Event: {title}', {'title': event.title}),
      when,
      ?event.locationText,
      chatEventStatusText(event, now),
      chatEventCountsText(event),
      if (event.myStatus != null)
        tr('Your answer: {answer}', {'answer': _answerLabel(event.myStatus!)}),
    ].join(', ');

    return _CardFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WeCordPressable(
            key: ValueKey('chat-event-card-${event.id}'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            pressedScale: 0.99,
            semanticLabel: summary,
            hint: tr('Opens the event'),
            excludeSemantics: true,
            onPressed: () =>
                showChatEventSheet(context, event.id, event.conversationId),
            builder: (context, states) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DateTile(time: event.startsAt.toLocal(), muted: dimmed),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (event.isPinned) ...[
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 14,
                                  color: c.muted,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  event.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                    height: 1.25,
                                    color: dimmed ? c.muted : c.ink,
                                    decoration:
                                        status == ChatEventStatus.cancelled
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            when,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: c.muted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: ChatEventStatusPill(event: event, now: now),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (event.locationText != null) ...[
                  const SizedBox(height: 10),
                  _InfoLine(
                    icon: Icons.place_outlined,
                    text: event.locationText!,
                  ),
                ],
                if (event.linkUrl != null) ...[
                  const SizedBox(height: 6),
                  _InfoLine(
                    icon: Icons.link_rounded,
                    text: chatEventLinkLabel(event.linkUrl!),
                    accent: true,
                  ),
                ],
                if (description != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, height: 1.4, color: c.ink),
                  ),
                ],
                const SizedBox(height: 12),
                ChatEventAttendees(event: event),
              ],
            ),
          ),
          if (status != ChatEventStatus.over) ...[
            const SizedBox(height: 12),
            ChatEventRsvpBar(event: event),
          ],
        ],
      ),
    );
  }
}

String _answerLabel(ChatEventRsvp status) => switch (status) {
  ChatEventRsvp.going => tr('Going'),
  ChatEventRsvp.maybe => tr('Maybe'),
  ChatEventRsvp.declined => tr("Can't"),
};

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.text,
    this.accent = false,
  });

  final IconData icon;
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      children: [
        Icon(icon, size: 17, color: accent ? c.accentText : c.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: accent ? c.accentText : c.ink,
            ),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------- Details

/// The event in full: description, place or link, who is coming, and what
/// can be done with it (answer, add to calendar, pin, edit, cancel).
Future<void> showChatEventSheet(
  BuildContext context,
  String eventId,
  String conversationId,
) {
  return showWeCordSheet<void>(
    context,
    detents: const [0.6, 0.92],
    builder: (context, scrollController) => _EventSheet(
      eventId: eventId,
      conversationId: conversationId,
      scrollController: scrollController,
    ),
  );
}

class _EventSheet extends ConsumerWidget {
  const _EventSheet({
    required this.eventId,
    required this.conversationId,
    required this.scrollController,
  });

  final String eventId;
  final String conversationId;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final event = chatEventById(
      ref.watch(chatEventsProvider(conversationId)).value,
      eventId,
    );
    final now = ref.watch(timeTokenClockProvider).value ?? DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final bottom = MediaQuery.paddingOf(context).bottom;

    if (event == null) {
      return Center(
        child: Text(
          tr('This event is no longer available.'),
          style: TextStyle(color: c.muted),
        ),
      );
    }
    final actions = ChatEventActions(ref, context);
    final status = event.statusAt(now);
    final description = event.description;
    final going = event.attendees.where((a) => a.status == ChatEventRsvp.going);
    final maybe = event.attendees.where((a) => a.status == ChatEventRsvp.maybe);

    Widget action(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool danger = false,
    }) {
      return SettingsRow(
        icon: icon,
        tone: danger ? SettingsTone.danger : SettingsTone.neutral,
        title: label,
        destructive: danger,
        onTap: onTap,
      );
    }

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DateTile(
              time: event.startsAt.toLocal(),
              muted:
                  status == ChatEventStatus.cancelled ||
                  status == ChatEventStatus.over,
              size: 60,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      event.title,
                      key: const ValueKey('chat-event-sheet-title'),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        height: 1.2,
                        color: c.ink,
                        decoration: status == ChatEventStatus.cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatChatEventWhen(event, now, use24Hour: use24Hour),
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ChatEventStatusPill(event: event, now: now),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (event.locationText != null || event.linkUrl != null)
          SettingsGroup(
            separatorIndent: 58,
            children: [
              if (event.locationText != null)
                SettingsRow(
                  icon: Icons.place_outlined,
                  title: event.locationText!,
                ),
              if (event.linkUrl != null)
                SettingsRow(
                  key: const ValueKey('chat-event-open-link'),
                  icon: Icons.link_rounded,
                  tone: SettingsTone.accent,
                  title: chatEventLinkLabel(event.linkUrl!),
                  subtitle: tr('Opens the link'),
                  onTap: () => actions.openLink(event),
                ),
            ],
          ),
        if (description != null) ...[
          const SizedBox(height: 14),
          MessageMarkdownText(body: description, color: c.ink),
        ],
        if (event.creatorName != null) ...[
          const SizedBox(height: 12),
          Text(
            tr('Created by {name}', {'name': event.creatorName}),
            style: TextStyle(fontSize: 12.5, color: c.subtle),
          ),
        ],
        if (status != ChatEventStatus.over &&
            status != ChatEventStatus.cancelled) ...[
          const SizedBox(height: 16),
          ChatEventRsvpBar(event: event),
        ],
        const SizedBox(height: 18),
        _AttendeeSection(
          title: tr('Going ({count})', {'count': event.goingCount}),
          people: going.toList(),
          hiddenCount: event.goingCount - going.length,
        ),
        _AttendeeSection(
          title: tr('Maybe ({count})', {'count': event.maybeCount}),
          people: maybe.toList(),
          hiddenCount: event.maybeCount - maybe.length,
        ),
        if (event.declinedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr("{count} can't make it", {'count': event.declinedCount}),
              style: TextStyle(fontSize: 13, color: c.subtle),
            ),
          ),
        const SizedBox(height: 18),
        SettingsGroup(
          separatorIndent: 58,
          children: [
            action(Icons.event_available_rounded, tr('Add to calendar'), () {
              actions.addToCalendar(event);
            }),
            if (event.canManage && !event.isCancelled)
              action(
                event.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                event.isPinned
                    ? tr('Unpin from chat header')
                    : tr('Pin to chat header'),
                () => actions.setPinned(event, !event.isPinned),
              ),
            if (event.canManage && !event.isCancelled)
              action(Icons.edit_outlined, tr('Edit event'), () async {
                final saved = await showChatEventEditor(
                  context,
                  conversationId: event.conversationId,
                  event: event,
                );
                if (saved != null) {
                  ref.invalidate(chatEventsProvider(event.conversationId));
                }
              }),
            if (event.canManage && !event.isCancelled)
              action(Icons.event_busy_outlined, tr('Cancel event'), () async {
                final confirmed = await _confirmCancel(context, event);
                if (confirmed == true) {
                  final done = await actions.cancel(event);
                  if (done && context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                }
              }, danger: true),
          ],
        ),
      ],
    );
  }
}

Future<bool?> _confirmCancel(BuildContext context, ChatEvent event) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      title: Text(tr('Cancel event?')),
      content: Text(
        tr(
          '"{title}" will be marked as cancelled and no one will be reminded of it.',
          {'title': event.title},
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Keep event')),
        ),
        FilledButton(
          key: const ValueKey('chat-event-confirm-cancel'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('Cancel event')),
        ),
      ],
    ),
  );
}

class _AttendeeSection extends StatelessWidget {
  const _AttendeeSection({
    required this.title,
    required this.people,
    required this.hiddenCount,
  });

  final String title;
  final List<ChatEventAttendee> people;
  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: c.subtle,
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final person in people)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  ChatAvatar(
                    name: person.name,
                    avatarUrl: person.avatarUrl,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (hiddenCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tr('and {count} more', {'count': hiddenCount}),
                style: TextStyle(fontSize: 13, color: c.subtle),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------ Header strip

/// Under the chat header: the pinned event with when it is and how many
/// are coming. Tapping opens it.
class ChatEventStrip extends ConsumerWidget {
  const ChatEventStrip({required this.conversationId, super.key});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(chatEventsProvider(conversationId)).value;
    if (events == null) {
      return const SizedBox.shrink();
    }
    final now = ref.watch(timeTokenClockProvider).value ?? DateTime.now();
    final event = pinnedChatEvent(events, now);
    if (event == null) {
      return const SizedBox.shrink();
    }
    final c = context.tokens.colors;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final desktop = MediaQuery.sizeOf(context).width >= 840;
    final live = event.statusAt(now) == ChatEventStatus.live;
    final detail =
        '${live ? tr('Live now') : formatChatEventWhen(event, now, use24Hour: use24Hour)}'
        ' · ${chatEventCountsText(event)}';
    return Padding(
      padding: desktop
          ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
          : const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: WeCordPressable(
        key: const ValueKey('chat-event-strip'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        semanticLabel: tr('Pinned event: {title}, {detail}', {
          'title': event.title,
          'detail': detail,
        }),
        hint: tr('Opens the event'),
        excludeSemantics: true,
        onPressed: () => showChatEventSheet(context, event.id, conversationId),
        builder: (context, states) => Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: states.contains(WidgetState.hovered)
                ? Color.alphaBlend(
                    c.accentText.withValues(alpha: 0.06),
                    c.accentSoft,
                  )
                : c.accentSoft,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              Icon(Icons.event_rounded, size: 20, color: c.accentText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: c.accentText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.accentText),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ List

/// All the chat's events: upcoming ones first, past ones below, with a
/// button to start a new one.
Future<void> showChatEventsList(
  BuildContext context, {
  required String conversationId,
  bool canCreate = true,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Events'),
    detents: const [0.6, 0.92],
    builder: (context, scrollController) => _EventsList(
      conversationId: conversationId,
      scrollController: scrollController,
      canCreate: canCreate,
    ),
  );
}

class _EventsList extends ConsumerWidget {
  const _EventsList({
    required this.conversationId,
    required this.scrollController,
    required this.canCreate,
  });

  final String conversationId;
  final ScrollController? scrollController;
  final bool canCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final events = ref.watch(chatEventsProvider(conversationId));
    final now = ref.watch(timeTokenClockProvider).value ?? DateTime.now();
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final all = events.value ?? const <ChatEvent>[];
    final upcoming = [
      for (final event in all)
        if (event.statusAt(now) == ChatEventStatus.upcoming ||
            event.statusAt(now) == ChatEventStatus.live)
          event,
    ];
    final past = [
      for (final event in all.reversed)
        if (event.statusAt(now) == ChatEventStatus.over ||
            event.statusAt(now) == ChatEventStatus.cancelled)
          event,
    ];

    Widget tile(ChatEvent event) {
      final status = event.statusAt(now);
      final dimmed =
          status == ChatEventStatus.over || status == ChatEventStatus.cancelled;
      return WeCordPressable(
        key: ValueKey('chat-event-row-${event.id}'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        semanticLabel: tr('{title}, {when}, {status}', {
          'title': event.title,
          'when': formatChatEventWhen(event, now, use24Hour: use24Hour),
          'status': chatEventStatusText(event, now),
        }),
        excludeSemantics: true,
        onPressed: () => showChatEventSheet(context, event.id, conversationId),
        builder: (context, states) => Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: states.contains(WidgetState.hovered) ? c.raised : null,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              _DateTile(
                time: event.startsAt.toLocal(),
                muted: dimmed,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: dimmed ? c.muted : c.ink,
                        decoration: status == ChatEventStatus.cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    Text(
                      '${formatChatEventWhen(event, now, use24Hour: use24Hour)} · ${chatEventStatusText(event, now)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ],
                ),
              ),
              if (event.myStatus != null)
                Icon(
                  switch (event.myStatus!) {
                    ChatEventRsvp.going => Icons.check_circle_rounded,
                    ChatEventRsvp.maybe => Icons.help_rounded,
                    ChatEventRsvp.declined => Icons.cancel_rounded,
                  },
                  size: 20,
                  color: switch (event.myStatus!) {
                    ChatEventRsvp.going => c.success,
                    ChatEventRsvp.maybe => c.warning,
                    ChatEventRsvp.declined => c.faint,
                  },
                ),
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        20 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        if (canCreate)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: WeCordButton(
              key: const ValueKey('chat-events-new'),
              label: tr('New event'),
              icon: Icons.add_rounded,
              variant: WeCordButtonVariant.accent,
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: () async {
                final created = await showChatEventEditor(
                  context,
                  conversationId: conversationId,
                );
                if (created != null) {
                  ref.invalidate(chatEventsProvider(conversationId));
                }
              },
            ),
          ),
        if (events.isLoading && all.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
            child: Text(
              tr('No events yet. Plan something with this chat.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, color: c.muted, height: 1.4),
            ),
          ),
        if (upcoming.isNotEmpty) ...[
          SettingsSectionHeader(tr('Upcoming')),
          for (final event in upcoming) tile(event),
        ],
        if (past.isNotEmpty) ...[
          SettingsSectionHeader(tr('Past')),
          for (final event in past) tile(event),
        ],
      ],
    );
  }
}
