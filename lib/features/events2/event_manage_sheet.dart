import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/events2/event_check_in.dart';
import 'package:wecord/features/events2/event_widgets.dart';
import 'package:wecord/shared/models/event_extras.dart';
import 'package:wecord/features/events2/events2_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Which event's sign-ups to list.
typedef EventRef = ({EventKind kind, String eventId});

/// The organiser's list of an event: who signed up (with their answers),
/// who waits, who came.
final eventRegistrationsProvider = FutureProvider.autoDispose
    .family<EventRegistrations, EventRef>((ref, key) {
      return ref
          .watch(events2RepositoryProvider)
          .listRegistrations(key.kind, key.eventId);
    });

/// Opens the organiser's view: the check-in code, the list of sign-ups with
/// their answers and ticks, the waiting list.
Future<void> showEventManageSheet(
  BuildContext context, {
  required EventKind kind,
  required String eventId,
  required String title,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Sign-ups and check-in'),
    detents: const [0.6, 0.92],
    builder: (context, scrollController) => EventManageSheet(
      kind: kind,
      eventId: eventId,
      title: title,
      scrollController: scrollController,
    ),
  );
}

/// The list as text a spreadsheet takes: one row per person, a column for each
/// question.
String eventRegistrationsTable(EventRegistrations data) {
  String cell(String? value) {
    final text = (value ?? '').replaceAll('\r', ' ').replaceAll('\n', ' ');
    return text.contains(',') || text.contains('"')
        ? '"${text.replaceAll('"', '""')}"'
        : text;
  }

  final header = [
    tr('Member'),
    tr('Response'),
    tr('Checked in'),
    for (final question in data.questions) question.label,
  ];
  final rows = <List<String>>[];
  for (final person in data.registrations) {
    rows.add([
      person.name,
      person.status ?? tr('Signed up'),
      person.checkedIn ? tr('Yes') : '',
      for (final question in data.questions) person.answers[question.id] ?? '',
    ]);
  }
  for (final person in data.waitlist) {
    rows.add([
      person.name,
      tr('Waiting list'),
      '',
      for (final question in data.questions) person.answers[question.id] ?? '',
    ]);
  }
  for (final person in data.walkIns) {
    rows.add([
      person.name,
      tr('Walk-in'),
      tr('Yes'),
      for (final _ in data.questions) '',
    ]);
  }
  return [header, ...rows].map((row) => row.map(cell).join(',')).join('\n');
}

class EventManageSheet extends ConsumerWidget {
  const EventManageSheet({
    required this.kind,
    required this.eventId,
    required this.title,
    this.scrollController,
    super.key,
  });

  final EventKind kind;
  final String eventId;
  final String title;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final key = (kind: kind, eventId: eventId);
    final data = ref.watch(eventRegistrationsProvider(key));
    final bottom = MediaQuery.paddingOf(context).bottom;

    return data.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is EventException
                    ? error.failure.message
                    : EventFailure.other.message,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted),
              ),
              const SizedBox(height: 10),
              WeCordButton(
                label: tr('Try again'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: () =>
                    ref.invalidate(eventRegistrationsProvider(key)),
              ),
            ],
          ),
        ),
      ),
      data: (list) {
        final summary = [
          tr('{count} signed up', {'count': list.registrations.length}),
          if (list.capacity != null)
            tr('{count} seats', {'count': list.capacity}),
          if (list.waitlist.isNotEmpty)
            tr('{count} on the waiting list', {'count': list.waitlist.length}),
          tr('{count} checked in', {'count': list.checkedInCount}),
        ].join(' · ');
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: c.muted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              summary,
              key: const ValueKey('event-manage-summary'),
              style: TextStyle(fontSize: 13.5, color: c.muted),
            ),
            const SizedBox(height: 12),
            SettingsGroup(
              separatorIndent: 58,
              children: [
                SettingsRow(
                  key: const ValueKey('event-manage-code'),
                  icon: Icons.qr_code_2_rounded,
                  tone: SettingsTone.accent,
                  title: tr('Show check-in code'),
                  subtitle: tr('People scan it to check in'),
                  onTap: () => unawaited(
                    showEventCheckInSheet(
                      context,
                      kind: kind,
                      eventId: eventId,
                      title: title,
                    ),
                  ),
                ),
                SettingsRow(
                  key: const ValueKey('event-manage-copy'),
                  icon: Icons.copy_rounded,
                  title: tr('Copy the list'),
                  subtitle: tr('As a table for a spreadsheet'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    await Clipboard.setData(
                      ClipboardData(text: eventRegistrationsTable(list)),
                    );
                    messenger?.showSnackBar(
                      SnackBar(content: Text(tr('The list was copied.'))),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PeopleSection(
              title: tr('Signed up ({count})', {
                'count': list.registrations.length,
              }),
              empty: tr('No one yet.'),
              people: list.registrations,
              questions: list.questions,
              tickable: true,
              kind: kind,
              eventId: eventId,
            ),
            if (list.waitlist.isNotEmpty) ...[
              const SizedBox(height: 16),
              _PeopleSection(
                title: tr('Waiting list ({count})', {
                  'count': list.waitlist.length,
                }),
                empty: '',
                people: list.waitlist,
                questions: list.questions,
                tickable: false,
                numbered: true,
                kind: kind,
                eventId: eventId,
              ),
            ],
            if (list.walkIns.isNotEmpty) ...[
              const SizedBox(height: 16),
              _PeopleSection(
                title: tr('Walked in ({count})', {
                  'count': list.walkIns.length,
                }),
                empty: '',
                people: list.walkIns,
                questions: const [],
                tickable: true,
                kind: kind,
                eventId: eventId,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _PeopleSection extends ConsumerWidget {
  const _PeopleSection({
    required this.title,
    required this.empty,
    required this.people,
    required this.questions,
    required this.tickable,
    required this.kind,
    required this.eventId,
    this.numbered = false,
  });

  final String title;
  final String empty;
  final List<EventRegistration> people;
  final List<EventQuestion> questions;
  final bool tickable;
  final bool numbered;
  final EventKind kind;
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.muted,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (people.isEmpty)
          Text(empty, style: TextStyle(fontSize: 14, color: c.muted))
        else
          Container(
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.xl),
              border: Border.all(color: c.lineSoft),
            ),
            child: Column(
              children: [
                for (final (index, person) in people.indexed) ...[
                  if (index > 0) Divider(height: 1, color: c.lineSoft),
                  _PersonRow(
                    key: ValueKey('event-person-${person.userId}'),
                    person: person,
                    position: numbered ? index + 1 : null,
                    questions: questions,
                    tickable: tickable,
                    onTick: (value) async {
                      final ok = await runEventAction(
                        context,
                        () => ref
                            .read(events2RepositoryProvider)
                            .setCheckedIn(
                              kind,
                              eventId,
                              person.userId,
                              checkedIn: value,
                            ),
                      );
                      if (ok) {
                        ref.invalidate(
                          eventRegistrationsProvider((
                            kind: kind,
                            eventId: eventId,
                          )),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.questions,
    required this.tickable,
    required this.onTick,
    this.position,
    super.key,
  });

  final EventRegistration person;
  final int? position;
  final List<EventQuestion> questions;
  final bool tickable;
  final ValueChanged<bool> onTick;

  String get _statusLabel => switch (person.status) {
    'going' => tr('Going'),
    'maybe' => tr('Maybe'),
    'declined' => tr("Can't"),
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final answers = [
      for (final question in questions)
        if ((person.answers[question.id] ?? '').isNotEmpty)
          '${question.label}: ${person.answers[question.id]}',
    ];
    final status = _statusLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (position != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8),
              child: Text(
                '$position',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.muted,
                ),
              ),
            ),
          ChatAvatar(
            name: person.name,
            avatarUrl: person.avatarUrl,
            size: 36,
            ringColor: c.well,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.isEmpty ? person.name : '${person.name} · $status',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                for (final line in answers)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        color: c.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (tickable)
            WeCordIconButton(
              key: ValueKey('event-tick-${person.userId}'),
              tooltip: person.checkedIn
                  ? tr('Undo check-in for {name}', {'name': person.name})
                  : tr('Check in {name}', {'name': person.name}),
              icon: person.checkedIn
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 40,
              iconSize: 22,
              variant: WeCordButtonVariant.ghost,
              onPressed: () => onTick(!person.checkedIn),
            ),
        ],
      ),
    );
  }
}
