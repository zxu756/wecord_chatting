import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/legal/legal_document.dart';
import 'package:wecord/features/legal/legal_screen.dart';
import 'package:wecord/features/reports/message_reports.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/report_reason.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the sheet that reports [message]. [senderName] is who the "Also
/// block" switch names. [circleId] is set for a circle channel: the report
/// then goes to the circle's moderators, else to the WeCord team. Returns
/// true once the report was sent.
Future<bool?> showReportMessageSheet(
  BuildContext context, {
  required ChatMessage message,
  required String senderName,
  String? circleId,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Report message'),
    builder: (_, _) => ReportMessageSheet(
      message: message,
      senderName: senderName,
      toModerators: circleId != null,
    ),
  );
}

/// Reason, details, "Also block" and "Include context" for reporting one
/// message (`report_message`). Pops with true once it was sent.
class ReportMessageSheet extends ConsumerStatefulWidget {
  const ReportMessageSheet({
    required this.message,
    required this.senderName,
    required this.toModerators,
    super.key,
  });

  final ChatMessage message;
  final String senderName;
  final bool toModerators;

  @override
  ConsumerState<ReportMessageSheet> createState() => _ReportMessageSheetState();
}

class _ReportMessageSheetState extends ConsumerState<ReportMessageSheet> {
  final _details = TextEditingController();
  var _reason = ReportReason.spam;
  var _includeContext = true;
  var _alsoBlock = false;
  var _submitting = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
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
          .read(messageReportsRepositoryProvider)
          .report(
            messageId: widget.message.id,
            reason: _reason,
            details: _details.text,
            includeContext: _includeContext,
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
      final message = reportFailureText(error);
      setState(() {
        _submitting = false;
        _error = message;
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
                      widget.toModerators
                          ? tr(
                              "This goes to this circle's moderators. The person "
                              "you report won't know it was you.",
                            )
                          : tr(
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
                        key: const ValueKey('report-reasons'),
                        color: c.well,
                        separatorIndent: 14,
                        children: [
                          for (final reason in ReportReason.values)
                            SettingsRow(
                              key: ValueKey('report-reason-${reason.value}'),
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
                      fieldKey: const ValueKey('report-details'),
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
                          key: const ValueKey('report-include-context'),
                          title: tr('Include context'),
                          subtitle: tr(
                            'Shares up to 5 messages before and after it, as you '
                            'see them. They are deleted 90 days after the report is '
                            'handled.',
                          ),
                          value: _includeContext,
                          onChanged: _submitting
                              ? null
                              : (value) =>
                                    setState(() => _includeContext = value),
                        ),
                        SettingsRow.toggle(
                          key: const ValueKey('report-also-block'),
                          title: tr('Also block {name}', {
                            'name': widget.senderName,
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
            // The way out stays in view however long the form is.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: WeCordPressable(
                      key: const ValueKey('report-guidelines-link'),
                      pressedScale: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      onPressed: () => unawaited(
                        openLegalDocument(context, LegalDocument.guidelines),
                      ),
                      builder: (context, states) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          tr('Read the Community Guidelines'),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: c.accentText,
                            decoration: states.contains(WidgetState.hovered)
                                ? TextDecoration.underline
                                : null,
                            decorationColor: c.accentText,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _error!,
                      key: const ValueKey('report-error'),
                      style: TextStyle(fontSize: 13.5, color: c.dangerText),
                    ),
                  ],
                  const SizedBox(height: 12),
                  WeCordButton(
                    key: const ValueKey('report-submit'),
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
