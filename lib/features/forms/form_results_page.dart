import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/forms/form_csv.dart';
import 'package:wecord/features/forms/form_export.dart';
import 'package:wecord/features/forms/form_inputs.dart';
import 'package:wecord/features/forms/form_models.dart';
import 'package:wecord/features/forms/form_repository.dart';
import 'package:wecord/features/forms/form_stats.dart';
import 'package:wecord/features/forms/form_validation.dart';
import 'package:wecord/features/forms/form_widgets.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the results page of [formId].
Future<void> openFormResults(BuildContext context, {required String formId}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => FormResultsPage(formId: formId),
    ),
  );
}

enum _ResultsTab { summary, table }

/// The answers of a form: what each question adds up to, a table with one
/// row per sheet, and (for the creator) the tools: remind the people who
/// have not answered, export CSV, close or reopen.
class FormResultsPage extends ConsumerStatefulWidget {
  const FormResultsPage({required this.formId, super.key});

  final String formId;

  @override
  ConsumerState<FormResultsPage> createState() => _FormResultsPageState();
}

class _FormResultsPageState extends ConsumerState<FormResultsPage> {
  var _tab = _ResultsTab.summary;
  var _busy = false;

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      ref
        ..invalidate(formProvider(widget.formId))
        ..invalidate(formResultsProvider(widget.formId));
      if (success != null && mounted) {
        _snack(success);
      }
    } on FormException catch (error) {
      ref.invalidate(formProvider(widget.formId));
      if (mounted) {
        _snack(error.message);
      }
    } on Object {
      if (mounted) {
        _snack(tr("That didn't work. Try again."));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _remind(FormSnapshot form) {
    return _run(() async {
      final count = await ref.read(formRepositoryProvider).remind(form);
      if (mounted) {
        _snack(
          count == 1
              ? tr('Reminded 1 person.')
              : tr('Reminded {count} people.', {'count': count}),
        );
      }
    });
  }

  Future<void> _export(FormSnapshot form, FormResults results) async {
    final contents = buildFormCsv(form, results);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final outcome = await ref
        .read(formFileExporterProvider)
        .exportCsv(
          fileName: formCsvFileName(form.title),
          contents: contents,
          origin: origin,
        );
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case FormExportOutcome.downloadStarted:
        _snack(tr('Download started.'));
      case FormExportOutcome.failed:
        _snack(tr("Couldn't export the answers."));
      case FormExportOutcome.shared:
      case FormExportOutcome.cancelled:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final formAsync = ref.watch(formProvider(widget.formId));
    final resultsAsync = ref.watch(formResultsProvider(widget.formId));
    final form = formAsync.value;
    final results = resultsAsync.value;

    Widget body;
    if (form == null || results == null) {
      final failed = formAsync.hasError || resultsAsync.hasError;
      body = failed
          ? FormNote(
              icon: Icons.bar_chart_rounded,
              text: tr("You can't see the results of this form."),
              action: WeCordButton(
                label: tr('Try again'),
                variant: WeCordButtonVariant.secondary,
                onPressed: () => ref
                  ..invalidate(formProvider(widget.formId))
                  ..invalidate(formResultsProvider(widget.formId)),
              ),
            )
          : const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    } else {
      body = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: WeCordSegmented<_ResultsTab>(
              expand: true,
              selected: _tab,
              onChanged: (tab) => setState(() => _tab = tab),
              semanticLabel: tr('Results view'),
              segments: [
                WeCordSegment(
                  key: const ValueKey('form-tab-summary'),
                  value: _ResultsTab.summary,
                  label: tr('Summary'),
                ),
                WeCordSegment(
                  key: const ValueKey('form-tab-table'),
                  value: _ResultsTab.table,
                  label: tr('Responses'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _tab == _ResultsTab.summary
                ? _SummaryView(
                    form: form,
                    results: results,
                    busy: _busy,
                    onRemind: () => unawaited(_remind(form)),
                    onExport: () => unawaited(_export(form, results)),
                    onClosed: (closed) => unawaited(
                      _run(
                        () => ref
                            .read(formRepositoryProvider)
                            .setClosed(form.id, closed: closed),
                        success: closed
                            ? tr('The form is closed.')
                            : tr('The form is open again.'),
                      ),
                    ),
                  )
                : _ResponsesTable(form: form, results: results),
          ),
        ],
      );
    }

    return FormPageFrame(
      pageKey: const ValueKey('form-results-page'),
      title: form?.title ?? tr('Results'),
      subtitle: form == null
          ? null
          : '${tr('Results')} · ${formCountText(form)}',
      maxWidth: 960,
      child: ColoredBox(color: c.panel, child: body),
    );
  }
}

class _SummaryView extends StatelessWidget {
  const _SummaryView({
    required this.form,
    required this.results,
    required this.busy,
    required this.onRemind,
    required this.onExport,
    required this.onClosed,
  });

  final FormSnapshot form;
  final FormResults results;
  final bool busy;
  final VoidCallback onRemind;
  final VoidCallback onExport;
  final ValueChanged<bool> onClosed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final now = DateTime.now();
    final closed = form.isClosed(now);
    final stats = formStats(form, results);
    final unfilled = results.unfilled;
    final mine = form.canManage;
    final canRemind = mine && !closed;

    final tools = <Widget>[
      if (canRemind)
        SettingsRow(
          key: const ValueKey('form-remind'),
          icon: Icons.notifications_active_outlined,
          tone: SettingsTone.warning,
          title: tr("Remind people who haven't filled it in"),
          subtitle: unfilled == null
              ? tr('Everyone who has not answered gets a notification.')
              : unfilled.isEmpty
              ? tr('Everyone has filled this in.')
              : tr('{count} people have not answered yet.', {
                  'count': unfilled.length,
                }),
          showChevron: false,
          onTap: busy || (unfilled != null && unfilled.isEmpty)
              ? null
              : onRemind,
        ),
      SettingsRow(
        key: const ValueKey('form-export'),
        icon: Icons.download_rounded,
        tone: SettingsTone.accent,
        title: tr('Export as CSV'),
        subtitle: results.anonymous
            ? tr('The file has the answers only, not who gave them.')
            : tr('One row for each person.'),
        showChevron: false,
        onTap: results.responses.isEmpty ? null : onExport,
      ),
      if (mine)
        SettingsRow(
          key: ValueKey(closed ? 'form-reopen' : 'form-close'),
          icon: closed ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
          title: closed ? tr('Reopen the form') : tr('Close the form'),
          subtitle: closed
              ? tr('People can fill it in again.')
              : tr('Nobody can send or change answers any more.'),
          showChevron: false,
          onTap: busy ? null : () => onClosed(!closed),
        ),
    ];

    return ListView(
      key: const ValueKey('form-summary-list'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _Headline(form: form, results: results),
        const SizedBox(height: 12),
        SettingsGroup(color: c.well, separatorIndent: 58, children: tools),
        const SizedBox(height: 16),
        if (results.responses.isEmpty)
          FormNote(icon: Icons.inbox_outlined, text: tr('No answers yet.'))
        else
          for (final (index, stat) in stats.indexed)
            _QuestionCard(index: index, stats: stat, results: results),
        if (unfilled != null && unfilled.isNotEmpty) ...[
          SettingsSectionHeader(
            tr('Not answered yet ({count})', {'count': unfilled.length}),
          ),
          Container(
            decoration: BoxDecoration(
              color: c.well,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
              border: Border.all(color: c.lineSoft),
            ),
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final person in unfilled.take(60))
                  _PersonChip(person: person),
                if (unfilled.length > 60)
                  Text(
                    tr('and {count} more', {'count': unfilled.length - 60}),
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.person});

  final FormPerson person;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final url = person.avatarUrl;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PersonAvatar(
            name: person.displayName,
            size: 24,
            image: url == null ? null : NetworkImage(url),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              person.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "12 of 30 people answered" over a bar.
class _Headline extends StatelessWidget {
  const _Headline({required this.form, required this.results});

  final FormSnapshot form;
  final FormResults results;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final answered = results.responses.length;
    final total = results.memberTotal;
    final text = form.settings.onePerPerson && total > 0
        ? tr('{count} of {total} people answered', {
            'count': answered,
            'total': total,
          })
        : tr('{count} answers', {'count': answered});
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
        border: Border.all(color: c.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            text,
            key: const ValueKey('form-headline'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          ),
          if (form.settings.onePerPerson && total > 0) ...[
            const SizedBox(height: 10),
            FormBar(fraction: answered / total, height: 10),
          ],
          if (results.anonymous) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.visibility_off_outlined, size: 16, color: c.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr('Anonymous: nobody can see who gave which answers.'),
                    style: TextStyle(fontSize: 12.5, color: c.muted),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionCard extends StatefulWidget {
  const _QuestionCard({
    required this.index,
    required this.stats,
    required this.results,
  });

  final int index;
  final FormFieldStats stats;
  final FormResults results;

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  var _showAll = false;

  static const _previewCount = 5;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final stats = widget.stats;
    final field = stats.field;
    final percentBase = stats.answered;

    Widget chart;
    if (stats.bars.isNotEmpty) {
      chart = Column(
        children: [
          if (stats.number case final number?) ...[
            _NumberSummary(summary: number),
            const SizedBox(height: 12),
          ],
          for (final bar in stats.bars)
            _BarLine(bar: bar, percentOf: percentBase),
        ],
      );
    } else if (stats.texts.isNotEmpty) {
      final shown = _showAll
          ? stats.texts
          : stats.texts.take(_previewCount).toList();
      chart = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final text in shown)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: c.raised,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              child: Text(
                text,
                style: TextStyle(fontSize: 14, height: 1.35, color: c.ink),
              ),
            ),
          if (stats.texts.length > _previewCount)
            Align(
              alignment: Alignment.centerLeft,
              child: WeCordButton(
                key: ValueKey('form-more-${field.id}'),
                label: _showAll
                    ? tr('Show fewer')
                    : tr('Show all {count}', {'count': stats.texts.length}),
                variant: WeCordButtonVariant.ghost,
                size: WeCordButtonSize.small,
                onPressed: () => setState(() => _showAll = !_showAll),
              ),
            ),
        ],
      );
    } else if (stats.images.isNotEmpty) {
      chart = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final image in stats.images.take(24))
            FormImageThumb(
              image: image,
              size: 84,
              onTap: () => unawaited(showFormImage(context, image)),
            ),
        ],
      );
    } else {
      chart = Text(
        tr('No answers to this question.'),
        style: TextStyle(fontSize: 13.5, color: c.muted),
      );
    }

    return Container(
      key: ValueKey('form-stats-${field.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
        border: Border.all(color: c.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '${widget.index + 1}. ${field.label}',
              style: TextStyle(
                fontSize: 15,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${formFieldTypeName(field.type)} · ${tr('{count} answered', {'count': stats.answered})}',
            style: TextStyle(fontSize: 12.5, color: c.muted),
          ),
          const SizedBox(height: 10),
          chart,
        ],
      ),
    );
  }
}

class _BarLine extends StatelessWidget {
  const _BarLine({required this.bar, required this.percentOf});

  final FormStatBar bar;
  final int percentOf;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final percent = percentOf == 0 ? 0 : (bar.count * 100 / percentOf).round();
    return Semantics(
      container: true,
      label: tr('{label}: {count} ({percent}%)', {
        'label': bar.label,
        'count': bar.count,
        'percent': percent,
      }),
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      bar.label,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${bar.count} · $percent%',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              // The bar is the share of the people who answered, like the number.
              FormBar(fraction: percentOf == 0 ? 0 : bar.count / percentOf),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberSummary extends StatelessWidget {
  const _NumberSummary({required this.summary});

  final FormNumberSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    Widget cell(String label, double value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(WeCordRadii.md),
        ),
        child: Column(
          children: [
            Text(
              formatNumber(double.parse(value.toStringAsFixed(2))),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 11.5, color: c.muted)),
          ],
        ),
      ),
    );
    return Row(
      children: [
        cell(tr('Smallest'), summary.min),
        const SizedBox(width: 6),
        cell(tr('Average'), summary.mean),
        const SizedBox(width: 6),
        cell(tr('Median'), summary.median),
        const SizedBox(width: 6),
        cell(tr('Largest'), summary.max),
      ],
    );
  }
}

/// One row for each sheet, one column for each question; scrolls sideways.
class _ResponsesTable extends StatelessWidget {
  const _ResponsesTable({required this.form, required this.results});

  final FormSnapshot form;
  final FormResults results;

  static const _nameWidth = 150.0;

  double _widthOf(FormFieldDef field) => switch (field.type) {
    FormFieldType.longText => 260,
    FormFieldType.number || FormFieldType.date => 120,
    FormFieldType.image => 110,
    _ => 180,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    if (results.responses.isEmpty) {
      return FormNote(icon: Icons.inbox_outlined, text: tr('No answers yet.'));
    }
    final anonymous = results.anonymous;
    final total =
        (anonymous ? 56.0 : _nameWidth) +
        form.fields.fold<double>(0, (sum, f) => sum + _widthOf(f));

    Widget cell(double width, Widget child, {bool header = false}) => SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      ),
    );

    final headerRow = Container(
      decoration: BoxDecoration(
        color: c.raised,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          cell(
            anonymous ? 56 : _nameWidth,
            Text(
              anonymous ? '#' : tr('Name'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: c.muted,
              ),
            ),
          ),
          for (final field in form.fields)
            cell(
              _widthOf(field),
              Text(
                field.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: c.muted,
                ),
              ),
            ),
        ],
      ),
    );

    return Scrollbar(
      child: SingleChildScrollView(
        key: const ValueKey('form-table-scroll'),
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: total < MediaQuery.sizeOf(context).width
              ? MediaQuery.sizeOf(context).width
              : total,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              headerRow,
              Expanded(
                child: ListView.builder(
                  itemCount: results.responses.length,
                  itemBuilder: (context, index) {
                    final response = results.responses[index];
                    final person = results.personById(response.userId);
                    return Container(
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: c.lineSoft)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          cell(
                            anonymous ? 56 : _nameWidth,
                            anonymous
                                ? Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: c.muted,
                                    ),
                                  )
                                : Text(
                                    person?.displayName ?? tr('Someone'),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: c.ink,
                                    ),
                                  ),
                          ),
                          for (final field in form.fields)
                            cell(
                              _widthOf(field),
                              _AnswerCell(
                                field: field,
                                value: response.answers[field.id],
                                results: results,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnswerCell extends StatelessWidget {
  const _AnswerCell({
    required this.field,
    required this.value,
    required this.results,
  });

  final FormFieldDef field;
  final Object? value;
  final FormResults results;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    if (!isAnswered(field, value)) {
      return Text('—', style: TextStyle(fontSize: 13.5, color: c.faint));
    }
    if (value is FormImageAnswer) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FormImageThumb(
          image: value! as FormImageAnswer,
          size: 56,
          onTap: () =>
              unawaited(showFormImage(context, value! as FormImageAnswer)),
        ),
      );
    }
    return Text(
      csvAnswer(field, value, results),
      style: TextStyle(fontSize: 13.5, height: 1.35, color: c.ink),
    );
  }
}
