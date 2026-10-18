import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/insights/insights_charts.dart';
import 'package:wecord/features/circles/insights/insights_models.dart';
import 'package:wecord/features/circles/insights/insights_repository.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Insights for a circle (circle settings → Insights).
void openCircleInsights(BuildContext context, CircleDetail detail) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => CircleInsightsScreen(circleId: detail.circle.id),
    ),
  );
}

/// How the circle is doing: members, activity, busy hours, channels, where
/// new people came from. Numbers under 5 show as "<5", retention is a ratio,
/// and nothing here is about one person.
class CircleInsightsScreen extends ConsumerStatefulWidget {
  const CircleInsightsScreen({required this.circleId, super.key});

  final String circleId;

  @override
  ConsumerState<CircleInsightsScreen> createState() =>
      _CircleInsightsScreenState();
}

class _CircleInsightsScreenState extends ConsumerState<CircleInsightsScreen> {
  var _range = 30;

  @override
  Widget build(BuildContext context) {
    final key = (circleId: widget.circleId, rangeDays: _range);
    final insights = ref.watch(circleInsightsProvider(key));
    return CirclePageScaffold(
      title: tr('Insights'),
      body: ListView(
        padding: circlePagePadding(context),
        children: [
          WeCordSegmented<int>(
            key: const ValueKey('insights-range'),
            expand: true,
            selected: _range,
            semanticLabel: tr('Range'),
            onChanged: (range) => setState(() => _range = range),
            segments: [
              for (final days in insightRanges)
                WeCordSegment(
                  key: ValueKey('insights-range-$days'),
                  value: days,
                  label: tr('{count} days', {'count': days}),
                ),
            ],
          ),
          ...insights.when<List<Widget>>(
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (error, _) => [
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: CircleEmptyState(
                  icon: Icons.insights_outlined,
                  title: tr('Could not load insights.'),
                  message: errorText(error),
                  action: WeCordButton(
                    label: tr('Try again'),
                    onPressed: () =>
                        ref.invalidate(circleInsightsProvider(key)),
                  ),
                ),
              ),
            ],
            data: (data) => _sections(context, data),
          ),
        ],
      ),
    );
  }

  List<Widget> _sections(BuildContext context, CircleInsights data) {
    final c = context.tokens.colors;
    final days = data.series;
    final first = days.isEmpty ? null : days.first.day;
    final last = days.isEmpty ? null : days.last.day;
    Widget dates() => first == null || last == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  insightDayLabel(first),
                  style: TextStyle(fontSize: 11, color: c.subtle),
                ),
                Text(
                  insightDayLabel(last),
                  style: TextStyle(fontSize: 11, color: c.subtle),
                ),
              ],
            ),
          );

    String barSummary(String what, List<InsightCount> values) {
      final shown = [
        for (final v in values)
          if (!v.isHidden) v.value,
      ];
      final top = shown.isEmpty ? 0 : shown.reduce(math.max);
      return tr('{what} per day, {days} days. Busiest day: {top}.', {
        'what': what,
        'days': values.length,
        'top': top,
      });
    }

    final messageValues = [for (final day in days) day.messages];
    final activeValues = [for (final day in days) day.active];
    return [
      if (data.small) ...[const SizedBox(height: 14), _SmallCircleNote()],
      const SizedBox(height: 14),
      _SummaryTiles(data: data),
      SettingsSectionHeader(tr('Members')),
      CircleCard(
        key: const ValueKey('insights-members'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MemberLineChart(days: days),
            dates(),
          ],
        ),
      ),
      SettingsSectionHeader(tr('Activity')),
      CircleCard(
        key: const ValueKey('insights-activity'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChartTitle(text: trIn('insights', 'Messages'), swatch: c.accent),
            const SizedBox(height: 8),
            DailyBarsChart(
              values: messageValues,
              color: c.accent,
              summary: barSummary(trIn('insights', 'Messages'), messageValues),
            ),
            dates(),
            const SizedBox(height: 18),
            _ChartTitle(text: tr('Active members'), swatch: c.success),
            const SizedBox(height: 8),
            DailyBarsChart(
              values: activeValues,
              color: c.success,
              summary: barSummary(tr('Active members'), activeValues),
            ),
            dates(),
            const _HiddenLegend(),
          ],
        ),
      ),
      SettingsSectionHeader(tr('Busiest hours')),
      CircleCard(
        key: const ValueKey('insights-heatmap'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WeekHeatmap(
              heatmap: data.heatmap,
              summary: _heatmapSummary(data.heatmap),
            ),
            const SizedBox(height: 12),
            const _HeatLegend(),
          ],
        ),
      ),
      SettingsSectionHeader(tr('Channels')),
      _Ranking(
        key: const ValueKey('insights-channels'),
        emptyText: tr('No channel activity yet.'),
        rows: [
          for (final channel in data.channels)
            _RankRow(
              title: '# ${channel.name}',
              value: channel.messages,
              unit: trIn('insights', 'Messages').toLowerCase(),
            ),
        ],
      ),
      SettingsSectionHeader(tr('Invite links')),
      _Ranking(
        key: const ValueKey('insights-invites'),
        emptyText: tr('No one joined with an invite link in this range.'),
        rows: [
          for (final invite in data.invites)
            _RankRow(
              title: invite.createdByName == null
                  ? tr('Invite link')
                  : tr('Link by {name}', {'name': invite.createdByName}),
              subtitle: [
                insightDayLabel(invite.createdAt.toLocal()),
                if (invite.revoked) tr('revoked'),
              ].join(' · '),
              value: invite.brought,
              detail: tr('still here {count}', {
                'count': invite.remaining.text,
              }),
              unit: tr('brought'),
            ),
        ],
      ),
      SettingsSectionHeader(tr('Who brought people')),
      _Ranking(
        key: const ValueKey('insights-inviters'),
        emptyText: tr('No one was brought in by a member in this range.'),
        rows: [
          for (final inviter in data.inviters)
            _RankRow(
              title: inviter.name,
              value: inviter.brought,
              detail: tr('still here {count}', {
                'count': inviter.remaining.text,
              }),
              unit: tr('brought'),
            ),
        ],
      ),
      SettingsSectionHeader(tr('Retention')),
      CircleCard(
        key: const ValueKey('insights-retention'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RatioRow(
              title: tr('Newcomers still here'),
              note: tr('Of the people who joined in this range'),
              ratio: data.retention.joinedKept,
            ),
            const SizedBox(height: 16),
            _RatioRow(
              title: tr('Came back'),
              note: tr(
                'Of the people active the week before last, the share active last week',
              ),
              ratio: data.retention.activeReturning,
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
        child: Text(
          tr(
            'Numbers under 5 show as <5, so no one can be picked out. '
            'Days are counted in UTC, and the map in your time zone.',
          ),
          style: TextStyle(fontSize: 12.5, height: 1.4, color: c.muted),
        ),
      ),
    ];
  }

  String _heatmapSummary(InsightHeatmap heatmap) {
    var best = 0;
    var bestDay = 0;
    var bestHour = 0;
    for (var day = 0; day < heatmap.rows.length; day++) {
      for (var hour = 0; hour < heatmap.rows[day].length; hour++) {
        final cell = heatmap.rows[day][hour];
        if (cell.value > best) {
          best = cell.value;
          bestDay = day;
          bestHour = hour;
        }
      }
    }
    if (best == 0) {
      return tr('Messages by weekday and hour: no busy hours to show yet.');
    }
    final names = [
      tr('Sun'),
      tr('Mon'),
      tr('Tue'),
      tr('Wed'),
      tr('Thu'),
      tr('Fri'),
      tr('Sat'),
    ];
    return tr('Messages by weekday and hour. Busiest: {day} at {hour}:00.', {
      'day': names[bestDay],
      'hour': bestHour,
    });
  }
}

class _SmallCircleNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CircleCard(
      key: const ValueKey('insights-small'),
      color: c.warningSoft,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 20, color: c.warningText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr(
                'Insights fill in once the circle has at least 5 members. '
                'Until then every number is hidden, so no one can be picked out.',
              ),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: c.warningText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTiles extends StatelessWidget {
  const _SummaryTiles({required this.data});

  final CircleInsights data;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      (tr('Members now'), data.membersNow),
      (tr('Joined'), data.totals.joined),
      (tr('Left'), data.totals.left),
      (tr('Active members'), data.totals.active),
      (trIn('insights', 'Messages'), data.totals.messages),
      (tr('Voice minutes'), data.totals.voiceMinutes),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, count) in tiles)
              SizedBox(
                width: width,
                child: _StatTile(label: label, count: count),
              ),
          ],
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.count});

  final String label;
  final InsightCount count;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      label: '$label, ${count.isHidden ? tr('fewer than 5') : count.text}',
      child: ExcludeSemantics(
        child: CircleCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count.text,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: count.isHidden ? c.subtle : c.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartTitle extends StatelessWidget {
  const _ChartTitle({required this.text, required this.swatch});

  final String text;
  final Color swatch;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: swatch,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// A hatched swatch that says what a hatched bar or cell means.
class _HatchSwatch extends StatelessWidget {
  const _HatchSwatch();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return CustomPaint(
      size: const Size(14, 14),
      painter: _HatchPainter(fill: c.raised, line: c.faint),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter({required this.fill, required this.line});

  final Color fill;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas
      ..drawRRect(rrect, Paint()..color = fill)
      ..save()
      ..clipRRect(rrect);
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var dx = -size.height; dx < size.width; dx += 4) {
      canvas.drawLine(
        Offset(dx, size.height),
        Offset(dx + size.height, 0),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.fill != fill || old.line != line;
}

class _HiddenLegend extends StatelessWidget {
  const _HiddenLegend();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          const _HatchSwatch(),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('Hatched: fewer than 5'),
              style: TextStyle(fontSize: 12, color: c.subtle),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend();

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    TextStyle small() => TextStyle(fontSize: 12, color: c.subtle);
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Quieter'), style: small()),
            const SizedBox(width: 6),
            for (final step in const [0, 1, 2, 3])
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  color: heatColor(c, step, 3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const SizedBox(width: 4),
            Text(tr('Busier'), style: small()),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _HatchSwatch(),
            const SizedBox(width: 6),
            Text(tr('Fewer than 5'), style: small()),
          ],
        ),
      ],
    );
  }
}

class _RankRow {
  const _RankRow({
    required this.title,
    required this.value,
    required this.unit,
    this.subtitle,
    this.detail,
  });

  final String title;
  final String? subtitle;
  final InsightCount value;

  /// A second figure under the first ("still here 9").
  final String? detail;

  /// What the figure counts ("messages", "brought").
  final String unit;
}

/// A ranked list inside one card: rank, name, a bar scaled to the first
/// row, and the figure ("<5" for a hidden one, which has no bar).
class _Ranking extends StatelessWidget {
  const _Ranking({required this.rows, required this.emptyText, super.key});

  final List<_RankRow> rows;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    if (rows.isEmpty) {
      return CircleCard(
        child: Text(
          emptyText,
          style: TextStyle(fontSize: 13.5, color: c.muted),
        ),
      );
    }
    final peak = rows.fold<int>(
      0,
      (high, row) => math.max(high, row.value.drawn),
    );
    return CircleCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.lineSoft),
            _RankTile(rank: i + 1, row: rows[i], peak: peak),
          ],
        ],
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({required this.rank, required this.row, required this.peak});

  final int rank;
  final _RankRow row;
  final int peak;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final fraction = peak == 0 ? 0.0 : row.value.drawn / peak;
    final figure = '${row.value.text} ${row.unit}';
    return Semantics(
      label: [
        '$rank',
        row.title,
        figure,
        if (row.detail != null) row.detail!,
      ].join(', '),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.subtle,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    if (row.subtitle != null)
                      Text(
                        row.subtitle!,
                        style: TextStyle(fontSize: 12.5, color: c.muted),
                      ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(height: 6, color: c.raised),
                          FractionallySizedBox(
                            widthFactor: fraction.clamp(0.0, 1.0),
                            child: Container(height: 6, color: c.accent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    row.value.text,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: row.value.isHidden ? c.subtle : c.ink,
                    ),
                  ),
                  Text(
                    row.unit,
                    style: TextStyle(fontSize: 11.5, color: c.subtle),
                  ),
                  if (row.detail != null)
                    Text(
                      row.detail!,
                      style: TextStyle(fontSize: 11.5, color: c.muted),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A ratio as a percentage with a bar, or a note that too few people stand
/// behind it.
class _RatioRow extends StatelessWidget {
  const _RatioRow({
    required this.title,
    required this.note,
    required this.ratio,
  });

  final String title;
  final String note;
  final double? ratio;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final ratio = this.ratio;
    final percent = ratio == null ? null : (ratio * 100).round();
    return Semantics(
      label: percent == null
          ? '$title, ${tr('not enough people to say')}'
          : '$title, $percent%',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                Text(
                  percent == null ? '—' : '$percent%',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: percent == null ? c.subtle : c.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              percent == null ? tr('Not enough people to say yet.') : note,
              style: TextStyle(fontSize: 12.5, height: 1.35, color: c.muted),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 8, color: c.raised),
                  FractionallySizedBox(
                    widthFactor: ((ratio ?? 0).clamp(0.0, 1.0)),
                    child: Container(height: 8, color: c.success),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
