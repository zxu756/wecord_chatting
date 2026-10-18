import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/agenda/agenda_models.dart';
import 'package:wecord/features/agenda/agenda_month_view.dart';
import 'package:wecord/features/agenda/agenda_navigation.dart';
import 'package:wecord/features/agenda/agenda_repository.dart';
import 'package:wecord/features/agenda/agenda_row.dart';
import 'package:wecord/features/agenda/agenda_settings_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

enum AgendaView { list, month }

/// My agenda: everything with a time that concerns me, from every chat and
/// circle I am in. A list (overdue first, then Today, Tomorrow, This week and
/// Later) and a month view. Overdue tasks and reminders are red, because
/// they need me.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({this.initialView = AgendaView.list, super.key});

  static const path = '/agenda';

  final AgendaView initialView;

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  late var _view = widget.initialView;

  Future<void> _refresh() async {
    ref.invalidate(agendaListProvider);
    ref.invalidate(agendaMonthProvider);
    try {
      await ref.read(agendaListProvider.future);
    } on Object {
      // The list shows the error itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Scaffold(
      key: const ValueKey('agenda-screen'),
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(
                  title: tr('Agenda'),
                  actions: [
                    WeCordIconButton(
                      key: const ValueKey('agenda-calendar-settings'),
                      icon: Icons.event_repeat_outlined,
                      tooltip: tr('Calendar subscription'),
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: () => openAgendaSettings(context),
                    ),
                    WeCordIconButton(
                      key: const ValueKey('agenda-refresh'),
                      icon: Icons.refresh_rounded,
                      tooltip: tr('Refresh'),
                      variant: WeCordButtonVariant.onPaper,
                      onPressed: _refresh,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: WeCordSegmented<AgendaView>(
                    key: const ValueKey('agenda-view-switch'),
                    expand: true,
                    selected: _view,
                    semanticLabel: tr('View'),
                    onChanged: (view) => setState(() => _view = view),
                    segments: [
                      WeCordSegment(
                        key: const ValueKey('agenda-view-list'),
                        value: AgendaView.list,
                        label: tr('List'),
                        icon: Icons.view_agenda_outlined,
                      ),
                      WeCordSegment(
                        key: const ValueKey('agenda-view-month'),
                        value: AgendaView.month,
                        label: tr('Month'),
                        icon: Icons.calendar_month_outlined,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: switch (_view) {
                    AgendaView.list => _AgendaList(onRefresh: _refresh),
                    AgendaView.month => AgendaMonthView(onRefresh: _refresh),
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _bucketTitle(AgendaBucket bucket) => switch (bucket) {
  AgendaBucket.overdue => tr('Needs you'),
  AgendaBucket.today => tr('Today'),
  AgendaBucket.tomorrow => tr('Tomorrow'),
  AgendaBucket.thisWeek => tr('This week'),
  AgendaBucket.later => trIn('agenda-bucket', 'Later'),
};

class _AgendaList extends ConsumerWidget {
  const _AgendaList({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final agenda = ref.watch(agendaListProvider);
    final now = clock.now();
    final bottom = 24 + MediaQuery.paddingOf(context).bottom;
    final firstDay = weekdayFromFirstDayIndex(
      MaterialLocalizations.of(context).firstDayOfWeekIndex,
    );

    Widget scrollable(List<Widget> children) => RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const ValueKey('agenda-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, 4, 16, bottom),
        children: children,
      ),
    );

    return agenda.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => scrollable([
        _Message(
          key: const ValueKey('agenda-error'),
          icon: Icons.cloud_off_outlined,
          title: tr('Could not load your agenda.'),
          message: tr('Pull down to try again.'),
          color: c.dangerText,
        ),
      ]),
      data: (items) {
        final groups = groupAgenda(items, now, firstDayOfWeek: firstDay);
        if (groups.isEmpty) {
          return scrollable([
            _Message(
              key: const ValueKey('agenda-empty'),
              icon: Icons.event_available_outlined,
              title: tr('Nothing on your agenda'),
              message: tr(
                'Events you join, tasks assigned to you, reminders and '
                'scheduled messages show up here.',
              ),
            ),
          ]);
        }
        return scrollable([
          for (final entry in groups.entries) ...[
            _BucketHeader(
              bucket: entry.key,
              count: entry.value.length,
              title: _bucketTitle(entry.key),
            ),
            Container(
              key: ValueKey('agenda-section-${entry.key.name}'),
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(WeCordRadii.xl),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in entry.value)
                    AgendaRow(
                      item: item,
                      now: now,
                      withDate:
                          entry.key == AgendaBucket.overdue ||
                          entry.key == AgendaBucket.thisWeek ||
                          entry.key == AgendaBucket.later,
                      onPressed: () => openAgendaItem(context, ref, item),
                    ),
                ],
              ),
            ),
          ],
        ]);
      },
    );
  }
}

class _BucketHeader extends StatelessWidget {
  const _BucketHeader({
    required this.bucket,
    required this.count,
    required this.title,
  });

  final AgendaBucket bucket;
  final int count;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final overdue = bucket == AgendaBucket.overdue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: overdue ? c.dangerText : c.subtle,
                ),
              ),
            ),
          ),
          if (overdue)
            CountBadge(
              count: count,
              size: 20,
              tone: BadgeTone.mention,
              semanticLabel: tr('{count} overdue', {'count': count}),
            ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.message,
    this.color,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
      child: Column(
        children: [
          ThingAvatar(
            size: 64,
            icon: icon,
            color: c.raised,
            foregroundColor: color ?? c.muted,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color ?? c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: c.muted, height: 1.4),
          ),
        ],
      ),
    );
  }
}
