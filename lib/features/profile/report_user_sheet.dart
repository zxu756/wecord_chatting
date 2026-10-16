import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/report_reason.dart';
import 'package:wecord/shared/ui/ui.dart';

Future<void> showReportUserSheet(BuildContext context, Profile profile) {
  return showWeCordSheet<void>(
    context,
    title: tr('Report {name}', {'name': profile.displayLabel}),
    builder: (_, _) => ReportUserSheet(profile: profile),
  );
}

class ReportUserSheet extends ConsumerStatefulWidget {
  const ReportUserSheet({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends ConsumerState<ReportUserSheet> {
  final _detailsController = TextEditingController();
  ReportReason _reason = ReportReason.spam;
  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    try {
      await ref
          .read(profileRepositoryProvider)
          .reportUser(
            targetUserId: widget.profile.id,
            reason: _reason,
            details: _detailsController.text,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }
      final message = tr('Could not submit report. Try again.');
      setState(() {
        _isSubmitting = false;
        _errorText = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        // Lifts the sheet above the keyboard, so the content scrolls
        // within the space left instead of hiding behind it.
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(
                  'Choose the closest reason. You can add details if helpful.',
                ),
                style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
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
                        onTap: _isSubmitting
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
                controller: _detailsController,
                enabled: !_isSubmitting,
                label: tr('Details'),
                maxLength: 1000,
                maxLines: 4,
                minLines: 3,
                inputFormatters: [LengthLimitingTextInputFormatter(1000)],
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorText!,
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ],
              const SizedBox(height: 16),
              WeCordButton(
                key: const ValueKey('report-submit'),
                label: _isSubmitting
                    ? tr('Submitting...')
                    : tr('Submit report'),
                size: WeCordButtonSize.large,
                variant: WeCordButtonVariant.danger,
                expand: true,
                onPressed: _isSubmitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
