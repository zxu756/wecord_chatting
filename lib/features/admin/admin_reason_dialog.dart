import 'package:flutter/material.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What an admin typed in an action's first step.
class AdminReason {
  const AdminReason({required this.reason, this.until});

  /// Why; kept in the audit log.
  final String reason;

  /// Where a suspension ends; null is for good (or no end was asked).
  final DateTime? until;
}

/// How long a suspension lasts.
enum _SuspensionLength {
  day(Duration(days: 1)),
  week(Duration(days: 7)),
  month(Duration(days: 30)),
  forever(null);

  const _SuspensionLength(this.duration);

  final Duration? duration;

  String get label => switch (this) {
    day => tr('1 day'),
    week => tr('7 days'),
    month => tr('30 days'),
    forever => tr('For good'),
  };
}

/// The first step of an action: a reason (required unless [reasonRequired]
/// is false) and, for a suspension of a person, how long it lasts. Null
/// when the admin cancels. Dangerous actions then ask again.
Future<AdminReason?> askAdminReason(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool withDuration = false,
  bool reasonRequired = true,
  DateTime? now,
}) {
  return showCircleDialog<AdminReason>(
    context,
    builder: (context) => _ReasonDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      withDuration: withDuration,
      reasonRequired: reasonRequired,
      now: now,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.withDuration,
    required this.reasonRequired,
    this.now,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool withDuration;
  final bool reasonRequired;
  final DateTime? now;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();
  var _length = _SuspensionLength.week;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _valid =>
      !widget.reasonRequired || _controller.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) {
      return;
    }
    final duration = widget.withDuration ? _length.duration : null;
    Navigator.of(context).pop(
      AdminReason(
        reason: _controller.text.trim(),
        until: duration == null
            ? null
            : (widget.now ?? DateTime.now()).add(duration),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CircleDialog(
      title: widget.title,
      message: widget.message,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.withDuration) ...[
            WeCordSegmented<_SuspensionLength>(
              expand: true,
              selected: _length,
              semanticLabel: tr('How long'),
              onChanged: (value) => setState(() => _length = value),
              segments: [
                for (final length in _SuspensionLength.values)
                  WeCordSegment(
                    value: length,
                    label: length.label,
                    key: ValueKey('admin-length-${length.name}'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          WeCordTextField(
            fieldKey: const ValueKey('admin-reason-field'),
            controller: _controller,
            label: widget.reasonRequired ? tr('Reason') : tr('Note (optional)'),
            hint: tr('Kept in the audit log'),
            maxLines: 3,
            minLines: 2,
            maxLength: 500,
            textInputAction: TextInputAction.newline,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        CircleDialogAction(
          key: const ValueKey('admin-reason-cancel'),
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('admin-reason-confirm'),
          label: widget.confirmLabel,
          onPressed: _valid ? _submit : null,
        ),
      ],
    );
  }
}
