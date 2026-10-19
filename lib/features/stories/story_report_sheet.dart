import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/stories/stories_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/report_reason.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the sheet that reports the daily [storyId] to the WeCord team.
/// [authorName] is who the "Also block" switch names. Returns true once the
/// report was sent.
Future<bool?> showReportStorySheet(
  BuildContext context, {
  required String storyId,
  required String authorName,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Report daily'),
    useRootNavigator: true,
    builder: (_, _) =>
        ReportStorySheet(storyId: storyId, authorName: authorName),
  );
}

/// Reason, details and "Also block" for reporting one daily (`report_story`).
/// Pops with true once it was sent.
class ReportStorySheet extends ConsumerStatefulWidget {
  const ReportStorySheet({
    required this.storyId,
    required this.authorName,
    super.key,
  });

  final String storyId;
  final String authorName;

  @override
  ConsumerState<ReportStorySheet> createState() => _ReportStorySheetState();
}

class _ReportStorySheetState extends ConsumerState<ReportStorySheet> {
  final _details = TextEditingController();
  var _reason = ReportReason.spam;
  var _alsoBlock = false;
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String _failureText(Object error) {
    if (error is PostgrestException) {
      switch (error.code) {
        case '54000':
          return tr(
            'You have sent too many reports today. Try again tomorrow.',
          );
        case 'P0002':
          return tr('This daily is no longer available.');
        case '22023':
          return tr('This daily cannot be reported.');
      }
    }
    return tr('Could not submit report. Try again.');
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(storiesRepositoryProvider)
          .report(
            widget.storyId,
            reason: _reason,
            details: _details.text,
            alsoBlock: _alsoBlock,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = _failureText(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr(
                        "This goes to the WeCord team. The person you report "
                        "won't know it was you.",
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Semantics(
                      container: true,
                      label: tr('Reason'),
                      child: SettingsGroup(
                        key: const ValueKey('story-report-reasons'),
                        color: c.well,
                        separatorIndent: 14,
                        children: [
                          for (final reason in ReportReason.values)
                            SettingsRow(
                              key: ValueKey('story-report-${reason.value}'),
                              title: reason.label,
                              trailing: reason == _reason
                                  ? Icon(
                                      Icons.check_rounded,
                                      size: 20,
                                      color: c.accent,
                                    )
                                  : const SizedBox(width: 20),
                              onTap: _submitting
                                  ? null
                                  : () {
                                      WeCordHaptics.selection();
                                      setState(() => _reason = reason);
                                    },
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    WeCordTextField(
                      fieldKey: const ValueKey('story-report-details'),
                      controller: _details,
                      enabled: !_submitting,
                      label: tr('Details'),
                      maxLength: 1000,
                      maxLines: 4,
                      minLines: 2,
                      inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                    ),
                    const SizedBox(height: 14),
                    SettingsGroup(
                      color: c.well,
                      children: [
                        SettingsRow.toggle(
                          key: const ValueKey('story-report-also-block'),
                          title: tr('Also block {name}', {
                            'name': widget.authorName,
                          }),
                          subtitle: tr("You won't see each other's messages."),
                          value: _alsoBlock,
                          onChanged: _submitting
                              ? null
                              : (value) => setState(() => _alsoBlock = value),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      key: const ValueKey('story-report-error'),
                      style: TextStyle(fontSize: 13.5, color: c.dangerText),
                    ),
                    const SizedBox(height: 8),
                  ],
                  WeCordButton(
                    key: const ValueKey('story-report-submit'),
                    label: _submitting
                        ? tr('Submitting...')
                        : tr('Submit report'),
                    size: WeCordButtonSize.large,
                    variant: WeCordButtonVariant.danger,
                    expand: true,
                    onPressed: _submitting ? null : _submit,
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
