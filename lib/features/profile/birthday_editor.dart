import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/profile/profile_social_models.dart';
import 'package:wecord/features/profile/profile_social_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The "Birthday" row of the profile settings: the saved day, or "Add".
class BirthdaySettingsRow extends ConsumerWidget {
  const BirthdaySettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myProfileExtrasProvider).value?.birthday;
    final birthday = mine?.birthday;
    return SettingsRow(
      key: const ValueKey('settings-birthday'),
      icon: Icons.cake_outlined,
      title: tr('Birthday'),
      value: birthday?.label ?? tr('Not set'),
      onTap: () async {
        final saved = await showBirthdayEditor(
          context,
          current: mine ?? const MyBirthday(),
        );
        if (saved == true) {
          ref.invalidate(myProfileExtrasProvider);
        }
      },
    );
  }
}

/// Opens the sheet to set, change or remove my birthday. Resolves to true
/// when something was saved.
Future<bool?> showBirthdayEditor(
  BuildContext context, {
  required MyBirthday current,
}) {
  return showWeCordSheet<bool>(
    context,
    title: tr('Birthday'),
    builder: (context, _) => BirthdayEditor(current: current),
  );
}

class BirthdayEditor extends ConsumerStatefulWidget {
  const BirthdayEditor({required this.current, super.key});

  final MyBirthday current;

  @override
  ConsumerState<BirthdayEditor> createState() => _BirthdayEditorState();
}

class _BirthdayEditorState extends ConsumerState<BirthdayEditor> {
  late int? _month = widget.current.birthday?.month;
  late int? _day = widget.current.birthday?.day;
  late BirthdayVisibility _visibility = widget.current.visibility;
  late bool _reminders = widget.current.reminders;
  var _saving = false;
  String? _errorText;

  static const _monthsEn = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _monthName(int month) =>
      AppStrings.isChinese ? '$month 月' : _monthsEn[month - 1];

  Future<void> _save({required bool remove}) async {
    if (!remove && (_month == null || _day == null)) {
      setState(() => _errorText = tr('Choose a month and a day.'));
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await ref
          .read(profileSocialRepositoryProvider)
          .setMyBirthday(
            birthday: remove
                ? null
                : ProfileBirthday(month: _month!, day: _day!),
            visibility: _visibility,
            reminders: _reminders,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = tr('Could not save your birthday. Try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final month = _month;
    final days = month == null ? 31 : ProfileBirthday.daysIn(month);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                'Only the month and the day are saved, never the year. '
                'Your friends are reminded on the day.',
              ),
              style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey('birthday-month'),
                    isExpanded: true,
                    initialValue: _month,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: trIn('birthday', 'Month'),
                    ),
                    items: [
                      for (var m = 1; m <= 12; m++)
                        DropdownMenuItem(value: m, child: Text(_monthName(m))),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _month = value;
                            if (value != null &&
                                _day != null &&
                                _day! > ProfileBirthday.daysIn(value)) {
                              _day = null;
                            }
                          }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('birthday-day-${_month ?? 0}'),
                    isExpanded: true,
                    initialValue: _day,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: tr('Day'),
                    ),
                    items: [
                      for (var d = 1; d <= days; d++)
                        DropdownMenuItem(value: d, child: Text('$d')),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _day = value),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
              child: Semantics(
                header: true,
                child: Text(
                  tr('Who can see this'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.subtle,
                  ),
                ),
              ),
            ),
            WeCordSegmented<BirthdayVisibility>(
              expand: true,
              selected: _visibility,
              semanticLabel: tr('Who can see this'),
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _visibility = value),
              segments: [
                WeCordSegment(
                  key: const ValueKey('birthday-visibility-friends'),
                  value: BirthdayVisibility.friends,
                  label: tr('Friends'),
                ),
                WeCordSegment(
                  key: const ValueKey('birthday-visibility-self'),
                  value: BirthdayVisibility.self,
                  label: tr('Only me'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SettingsGroup(
              color: c.well,
              separatorIndent: 14,
              children: [
                SettingsRow.toggle(
                  key: const ValueKey('birthday-reminders'),
                  title: tr("Remind me of friends' birthdays"),
                  value: _reminders,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _reminders = value),
                ),
              ],
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ],
            const SizedBox(height: 18),
            WeCordButton(
              key: const ValueKey('birthday-save'),
              label: tr('Save'),
              expand: true,
              loading: _saving,
              onPressed: _saving ? null : () => _save(remove: false),
            ),
            if (widget.current.birthday != null) ...[
              const SizedBox(height: 8),
              WeCordButton(
                key: const ValueKey('birthday-remove'),
                label: tr('Remove birthday'),
                variant: WeCordButtonVariant.secondary,
                expand: true,
                onPressed: _saving ? null : () => _save(remove: true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
