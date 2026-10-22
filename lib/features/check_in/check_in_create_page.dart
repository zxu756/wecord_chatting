import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/check_in/check_in_models.dart';
import 'package:wecord/features/check_in/check_in_repository.dart';
import 'package:wecord/features/forms/form_widgets.dart' show FormPageFrame;
import 'package:wecord/features/notifications/device_time_zone.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the page that makes a check-in for [conversationId]. Resolves to
/// true once the card is posted.
Future<bool?> showCheckInCreate(
  BuildContext context, {
  required String conversationId,
}) {
  return Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute<bool>(
      builder: (context) => CheckInCreatePage(conversationId: conversationId),
    ),
  );
}

/// The form that starts a daily check-in: a title, what it is for, an
/// optional reminder time and an optional last day.
class CheckInCreatePage extends ConsumerStatefulWidget {
  const CheckInCreatePage({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<CheckInCreatePage> createState() => _CheckInCreatePageState();
}

class _CheckInCreatePageState extends ConsumerState<CheckInCreatePage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  int? _remindMinute;
  DateTime? _endsOn;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final now = _remindMinute ?? 20 * 60;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: now ~/ 60, minute: now % 60),
    );
    if (picked != null && mounted) {
      setState(() => _remindMinute = picked.hour * 60 + picked.minute);
    }
  }

  Future<void> _pickEnd() async {
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _endsOn ?? first.add(const Duration(days: 30)),
      firstDate: first,
      lastDate: first.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) {
      setState(() => _endsOn = picked);
    }
  }

  Future<void> _post() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = tr('Give the check-in a title.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(checkInRepositoryProvider)
          .create(
            widget.conversationId,
            CheckInDraft(
              title: title,
              description: _description.text,
              timeZone: deviceTimeZone(),
              remindMinute: _remindMinute,
              endsOn: _endsOn,
            ),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on CheckInException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = tr("That didn't work. Try again.");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final loc = MaterialLocalizations.of(context);
    return FormPageFrame(
      pageKey: const ValueKey('check-in-create-page'),
      title: tr('New check-in'),
      subtitle: tr('Once a day, with a streak'),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                key: const ValueKey('check-in-create-error'),
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ),
          WeCordButton(
            key: const ValueKey('check-in-post'),
            label: tr('Post check-in'),
            variant: WeCordButtonVariant.accent,
            size: WeCordButtonSize.large,
            expand: true,
            loading: _busy,
            onPressed: _busy ? null : () => unawaited(_post()),
          ),
        ],
      ),
      child: ListView(
        key: const ValueKey('check-in-create-list'),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          WeCordTextField(
            fieldKey: const ValueKey('check-in-title-field'),
            controller: _title,
            label: tr('Title'),
            hint: tr('Read 20 pages'),
            maxLength: 120,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          WeCordTextField(
            fieldKey: const ValueKey('check-in-description-field'),
            controller: _description,
            label: tr('Description (optional)'),
            hint: tr('Post a note or a picture of your day.'),
            maxLines: 4,
            minLines: 2,
            maxLength: 1000,
          ),
          SettingsSectionHeader(tr('Settings')),
          SettingsGroup(
            color: c.well,
            children: [
              SettingsRow.toggle(
                key: const ValueKey('check-in-setting-remind'),
                icon: Icons.notifications_active_outlined,
                title: tr('Daily reminder'),
                subtitle: tr('Reminds the people who have not checked in yet.'),
                value: _remindMinute != null,
                onChanged: (on) =>
                    setState(() => _remindMinute = on ? 20 * 60 : null),
              ),
              if (_remindMinute != null)
                SettingsRow(
                  key: const ValueKey('check-in-setting-remind-time'),
                  icon: Icons.schedule_rounded,
                  title: tr('Reminder time'),
                  value: TimeOfDay(
                    hour: _remindMinute! ~/ 60,
                    minute: _remindMinute! % 60,
                  ).format(context),
                  onTap: () => unawaited(_pickTime()),
                ),
              SettingsRow(
                key: const ValueKey('check-in-setting-end'),
                icon: Icons.event_outlined,
                title: tr('Last day'),
                value: _endsOn == null
                    ? tr('None')
                    : loc.formatMediumDate(_endsOn!),
                onTap: () => unawaited(_pickEnd()),
              ),
              if (_endsOn != null)
                SettingsRow(
                  key: const ValueKey('check-in-setting-end-clear'),
                  icon: Icons.close_rounded,
                  title: tr('Remove last day'),
                  showChevron: false,
                  onTap: () => setState(() => _endsOn = null),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              tr(
                'A new day starts at midnight in your time zone, so everyone in the group checks in for the same day.',
              ),
              style: TextStyle(fontSize: 12.5, height: 1.4, color: c.subtle),
            ),
          ),
        ],
      ),
    );
  }
}
