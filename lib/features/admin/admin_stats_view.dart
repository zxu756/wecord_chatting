import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/admin/admin_ops_models.dart'
    show adminPlatformLabel;
import 'package:wecord/features/admin/admin_stats_charts.dart';
import 'package:wecord/features/admin/admin_stats_models.dart';
import 'package:wecord/features/admin/admin_stats_repository.dart';
import 'package:wecord/features/admin/admin_repository.dart';
import 'package:wecord/features/admin/admin_widgets.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/insights/insights_charts.dart'
    show DailyBarsChart, insightDayLabel;
import 'package:wecord/features/circles/insights/insights_models.dart'
    show InsightCount;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The numbers for a range of days. The server answers counts only.
final opsMetricsProvider = FutureProvider.autoDispose.family<OpsMetrics, int>((
  ref,
  rangeDays,
) {
  return ref.watch(adminStatsRepositoryProvider).metrics(rangeDays: rangeDays);
});

/// The console's "Stats" tab (K2): how many people use WeCord and what they
/// use, from numbers the server adds up once a day. There is no tracking in
/// the apps; people are only ever counted, never listed.
class AdminStatsView extends ConsumerStatefulWidget {
  const AdminStatsView({super.key});

  @override
  ConsumerState<AdminStatsView> createState() => _AdminStatsViewState();
}

class _AdminStatsViewState extends ConsumerState<AdminStatsView> {
  var _range = 30;

  @override
  Widget build(BuildContext context) {
    final metrics = ref.watch(opsMetricsProvider(_range));
    return ListView(
      key: const ValueKey('admin-stats-list'),
      padding: circlePagePadding(context),
      children: [
        // Chips that wrap, so the range fits a narrow screen at the largest
        // text size (a segmented control would not).
        Semantics(
          container: true,
          label: tr('Range'),
          child: Wrap(
            key: const ValueKey('admin-stats-range'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final days in opsRanges)
                WeCordChip(
                  key: ValueKey('admin-stats-range-$days'),
                  label: tr('{count} days', {'count': days}),
                  selected: _range == days,
                  onPaper: true,
                  onPressed: () => setState(() => _range = days),
                ),
            ],
          ),
        ),
        ...metrics.when<List<Widget>>(
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
                title: tr('Could not load the stats.'),
                message: adminErrorText(error),
                action: WeCordButton(
                  label: tr('Retry'),
                  variant: WeCordButtonVariant.onPaper,
                  onPressed: () => ref.invalidate(opsMetricsProvider(_range)),
                ),
              ),
            ),
          ],
          data: (data) => _sections(context, data),
        ),
      ],
    );
  }

  List<Widget> _sections(BuildContext context, OpsMetrics data) {
    final c = context.tokens.colors;
    final days = data.days;
    final latest = data.latest;
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

    final activeValues = [for (final day in days) day.activeUsers];
    final messageValues = [
      for (final day in days) InsightCount(day.messagesTotal),
    ];
    final cohorts = data.cohorts.take(8).toList();
    final pushAttempts = data.totalPushSent + data.totalPushFailed;
    final features = data.featureCounts;
    final storageBytes = data.storageBytes;

    return [
      const SizedBox(height: 14),
      _Tiles(
        tiles: [
          _Tile(
            key: const ValueKey('admin-stats-today'),
            label: tr('Active today'),
            value: opsNumber(latest?.activeUsers ?? 0),
          ),
          _Tile(
            key: const ValueKey('admin-stats-week'),
            label: tr('Active this week'),
            value: opsNumber(data.wau),
          ),
          _Tile(
            key: const ValueKey('admin-stats-month'),
            label: tr('Active this month'),
            value: opsNumber(data.mau),
          ),
          _Tile(
            key: const ValueKey('admin-stats-new'),
            label: tr('New people'),
            value: opsNumber(data.totalNewUsers),
            caption: tr('in {count} days', {'count': _range}),
          ),
        ],
      ),
      SettingsSectionHeader(tr('Active people')),
      CircleCard(
        key: const ValueKey('admin-stats-active'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OpsLineChart(
              values: activeValues,
              color: c.accent,
              fill: c.accentSoft,
              summary: activeValues.isEmpty
                  ? tr('No numbers to show yet.')
                  : tr(
                      'Active people per day, {days} days. Busiest day: {top}.',
                      {
                        'days': activeValues.length,
                        'top': activeValues.reduce((a, b) => a > b ? a : b),
                      },
                    ),
            ),
            dates(),
          ],
        ),
      ),
      SettingsSectionHeader(tr('Coming back')),
      CircleCard(
        key: const ValueKey('admin-stats-retention'),
        child: cohorts.isEmpty
            ? Text(
                tr('Nobody new yet in this range.'),
                style: TextStyle(fontSize: 13.5, color: c.muted),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Of the people who joined on a day, the share who were '
                      'active again 1, 7 and 30 days later.',
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _RetentionRow(
                    key: const ValueKey('admin-stats-retention-head'),
                    cells: [
                      trIn('Stats', 'Day'),
                      trIn('Stats', 'New'),
                      tr('Next day'),
                      tr('7 days'),
                      tr('30 days'),
                    ],
                    header: true,
                  ),
                  for (final day in cohorts)
                    _RetentionRow(
                      key: ValueKey(
                        'admin-stats-cohort-${insightDayLabel(day.day)}',
                      ),
                      cells: [
                        insightDayLabel(day.day),
                        opsNumber(day.newUsers),
                        opsPercent(day.d1Retained, day.newUsers),
                        opsPercent(day.d7Retained, day.newUsers),
                        opsPercent(day.d30Retained, day.newUsers),
                      ],
                    ),
                ],
              ),
      ),
      SettingsSectionHeader(tr('Messages')),
      CircleCard(
        key: const ValueKey('admin-stats-messages'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DailyBarsChart(
              values: messageValues,
              color: c.accent,
              summary: tr('Messages per day, {days} days. {total} in all.', {
                'days': messageValues.length,
                'total': opsNumber(data.totalMessages),
              }),
            ),
            dates(),
            const SizedBox(height: 12),
            for (final entry in data.messagesByType)
              _FactRow(
                label: _messageTypeLabel(entry.key),
                value: opsNumber(entry.value),
              ),
            if (data.messagesByType.isEmpty)
              Text(
                tr('No messages in this range.'),
                style: TextStyle(fontSize: 13.5, color: c.muted),
              ),
          ],
        ),
      ),
      SettingsSectionHeader(tr('What people use')),
      CircleCard(
        key: const ValueKey('admin-stats-usage'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in features)
              _FactRow(
                label: _featureLabel(entry.key),
                value: opsNumber(entry.value),
              ),
            _FactRow(
              label: tr('Voice channel minutes'),
              value: opsNumber(data.totalVoiceMinutes),
            ),
            _FactRow(
              label: tr('AI requests'),
              value: opsNumber(data.totalAiRequests),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                tr(
                  'Voice minutes are counted from a look every 15 minutes, '
                  'so they are close, not exact.',
                ),
                style: TextStyle(fontSize: 12, height: 1.4, color: c.muted),
              ),
            ),
          ],
        ),
      ),
      SettingsSectionHeader(tr('Health')),
      CircleCard(
        key: const ValueKey('admin-stats-health'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FactRow(
              label: tr('Pushes delivered'),
              value: pushAttempts == 0
                  ? opsNumber(data.totalPushSent)
                  : '${opsNumber(data.totalPushSent)} '
                        '(${opsPercent(data.totalPushSent, pushAttempts)})',
            ),
            _FactRow(
              label: tr('Pushes failed'),
              value: opsNumber(data.totalPushFailed),
            ),
            _FactRow(
              label: tr('Dead push subscriptions removed'),
              value: opsNumber(data.totalPushGone),
            ),
            _FactRow(
              label: tr('Error reports'),
              value: opsNumber(data.totalErrorReports),
            ),
            _FactRow(
              label: tr('Storage in use'),
              value: storageBytes == null ? '–' : opsBytes(storageBytes),
            ),
            _FactRow(
              label: tr('Storage added'),
              value: opsBytes(data.totalStorageAdded),
            ),
          ],
        ),
      ),
      SettingsSectionHeader(tr('App versions, last 7 days')),
      CircleCard(
        key: const ValueKey('admin-stats-versions'),
        child: data.versions.isEmpty
            ? Text(
                tr('No version has reported yet.'),
                style: TextStyle(fontSize: 13.5, color: c.muted),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final version in data.versions)
                    _VersionRow(version: version),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      tr(
                        'Crash-free is the share of active people who did not '
                        'hit a crash. Reports from signed-out people are not '
                        'counted here.',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: c.muted,
                      ),
                    ),
                  ),
                ],
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
        child: Text(
          tr(
            'Only counts are kept. Nothing is measured on devices, no message '
            'is read, and people are counted from a scrambled key that is '
            'deleted after 45 days. Days are UTC.',
          ),
          style: TextStyle(fontSize: 12.5, height: 1.4, color: c.muted),
        ),
      ),
    ];
  }
}

String _messageTypeLabel(String type) => switch (type) {
  'text' => tr('Text'),
  'image' => tr('Photos'),
  'file' => tr('Files'),
  'voice' => tr('Voice messages'),
  'poll' => tr('Polls'),
  'sticker' => tr('Stickers'),
  'system' => tr('System notices'),
  _ => type,
};

String _featureLabel(String key) => switch (key) {
  'circle_posts' => tr('Circle posts'),
  'moments' => tr('Moments'),
  'stories' => tr('Dailies'),
  'notes' => tr('Notes'),
  'tasks' => tr('Tasks'),
  'chat_events' => tr('Chat events'),
  _ => key,
};

/// A row of big numbers.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.tiles});

  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final perRow = constraints.maxWidth >= 640 ? 4 : 2;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.value,
    this.caption,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final caption = this.caption;
    return Semantics(
      container: true,
      label: [label, value, ?caption].join(', '),
      child: ExcludeSemantics(
        child: CircleCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: c.muted,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: c.ink,
                    height: 1.1,
                  ),
                ),
              ),
              if (caption != null)
                Text(caption, style: TextStyle(fontSize: 12, color: c.subtle)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A label with its number, wrapping when the text is large.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Semantics(
        container: true,
        label: '$label: $value',
        child: ExcludeSemantics(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, color: c.ink, height: 1.3),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the retention table: five cells.
class _RetentionRow extends StatelessWidget {
  const _RetentionRow({required this.cells, this.header = false, super.key});

  final List<String> cells;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      container: true,
      label: header
          ? null
          : tr(
              '{day}: {new} new, {d1} next day, {d7} after 7 days, {d30} after 30 days',
              {
                'day': cells[0],
                'new': cells[1],
                'd1': cells[2],
                'd7': cells[3],
                'd30': cells[4],
              },
            ),
      child: ExcludeSemantics(
        excluding: !header,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              for (final (index, cell) in cells.indexed)
                Expanded(
                  flex: index == 0 ? 3 : 2,
                  child: Align(
                    alignment: index == 0
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        cell,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: header ? 12 : 14,
                          fontWeight: header
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: header ? c.subtle : c.ink,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.version});

  final OpsVersion version;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final free = (100 * version.crashFree).round();
    final tone = version.crashFree < 0.9
        ? SettingsTone.danger
        : version.crashFree < 0.95
        ? SettingsTone.warning
        : SettingsTone.success;
    final platform = _platformName(version.platform);
    final label = tr('{version} on {platform}', {
      'version': version.appVersion,
      'platform': platform,
    });
    final people = tr('{count} active', {
      'count': opsNumber(version.activeUsers),
    });
    final crashFree = tr('{percent}% crash-free', {'percent': free});
    return Padding(
      key: ValueKey(
        'admin-stats-version-${version.appVersion}-${version.platform}',
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        container: true,
        label: '$label, $people, $crashFree',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              // Wraps instead of overflowing at the largest text size.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    people,
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                  AdminStateTag(label: crashFree, tone: tone),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A platform in words ('ios' is iOS, 'macos' macOS).
String _platformName(String platform) =>
    platform.isEmpty ? tr('unknown') : adminPlatformLabel(platform);
