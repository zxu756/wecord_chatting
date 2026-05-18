import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/report_reason.dart';

Future<void> showReportUserSheet(BuildContext context, Profile profile) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ReportUserSheet(profile: profile),
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
      const message = 'Could not submit report. Try again.';
      setState(() {
        _isSubmitting = false;
        _errorText = message;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Report ${widget.profile.displayLabel}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose the closest reason. You can add details if helpful.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            RadioGroup<ReportReason>(
              groupValue: _reason,
              onChanged: (value) {
                if (_isSubmitting || value == null) {
                  return;
                }
                setState(() => _reason = value);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final reason in ReportReason.values)
                    RadioListTile<ReportReason>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(reason.label),
                      value: reason,
                      enabled: !_isSubmitting,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _detailsController,
              enabled: !_isSubmitting,
              maxLength: 1000,
              maxLines: 4,
              inputFormatters: [LengthLimitingTextInputFormatter(1000)],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Details',
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: Text(_isSubmitting ? 'Submitting...' : 'Submit report'),
            ),
          ],
        ),
      ),
    );
  }
}
