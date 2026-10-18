import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/friend_tags/friend_picker.dart';
import 'package:wecord/features/notifications/notification_settings.dart';
import 'package:wecord/features/notifications/notification_settings_controller.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings -> Notifications -> Quiet hours.
void openQuietHours(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const QuietHoursScreen()),
  );
}

/// "10:30 PM" or "22:30", as the device writes times.
String quietTimeLabel(BuildContext context, QuietTime time) {
  return MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay(hour: time.hour, minute: time.minute));
}

/// The window in a few words: "10:00 PM – 7:00 AM".
String quietWindowLabel(BuildContext context, NotificationSettings settings) {
  return '${quietTimeLabel(context, settings.quietStart)} – '
      '${quietTimeLabel(context, settings.quietEnd)}';
}

/// The "Quiet hours" row of Settings -> Notifications.
class QuietHoursSettingsRow extends ConsumerWidget {
  const QuietHoursSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(notificationSettingsProvider).value ??
        NotificationSettings.defaults;
    return SettingsRow(
      key: const ValueKey('quiet-hours-tile'),
      icon: Icons.bedtime_outlined,
      title: tr('Quiet hours'),
      value: settings.quietEnabled
          ? quietWindowLabel(context, settings)
          : tr('Off'),
      onTap: () => openQuietHours(context),
    );
  }
}

String _shortDay(int isoWeekday) => switch (isoWeekday) {
  1 => tr('Mon'),
  2 => tr('Tue'),
  3 => tr('Wed'),
  4 => tr('Thu'),
  5 => tr('Fri'),
  6 => tr('Sat'),
  _ => tr('Sun'),
};

String _longDay(int isoWeekday) => switch (isoWeekday) {
  1 => tr('Monday'),
  2 => tr('Tuesday'),
  3 => tr('Wednesday'),
  4 => tr('Thursday'),
  5 => tr('Friday'),
  6 => tr('Saturday'),
  _ => tr('Sunday'),
};

/// Settings -> Notifications -> Quiet hours: the switch, the window and its
/// weekdays, and what still gets through.
class QuietHoursScreen extends ConsumerWidget {
  const QuietHoursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final settings =
        ref.watch(notificationSettingsProvider).value ??
        NotificationSettings.defaults;
    final on = settings.quietEnabled;
    final vipCount = settings.vipUserIds.length;
    final zone = settings.timezone;
    return SettingsPage(
      key: const ValueKey('quiet-hours-screen'),
      title: tr('Quiet hours'),
      children: [
        const SizedBox(height: 12),
        SettingsGroup(
          children: [
            SettingsRow.toggle(
              key: const ValueKey('quiet-hours-switch'),
              icon: Icons.bedtime_outlined,
              tone: on ? SettingsTone.accent : SettingsTone.neutral,
              title: tr('Quiet hours'),
              subtitle: tr('No push notifications in this window'),
              value: on,
              onChanged: (value) => unawaited(
                _save(context, ref, settings.copyWith(quietEnabled: value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsGroup(
          header: tr('Schedule'),
          children: [
            SettingsRow(
              key: const ValueKey('quiet-hours-start'),
              icon: Icons.nights_stay_outlined,
              title: tr('Quiet hours start'),
              value: quietTimeLabel(context, settings.quietStart),
              onTap: on
                  ? () => unawaited(
                      _pickTime(context, ref, settings, start: true),
                    )
                  : null,
              showChevron: on,
            ),
            SettingsRow(
              key: const ValueKey('quiet-hours-end'),
              icon: Icons.wb_sunny_outlined,
              title: tr('Quiet hours end'),
              subtitle: settings.crossesMidnight
                  ? tr('The next morning')
                  : null,
              value: quietTimeLabel(context, settings.quietEnd),
              onTap: on
                  ? () => unawaited(
                      _pickTime(context, ref, settings, start: false),
                    )
                  : null,
              showChevron: on,
            ),
            SettingsRow(
              key: const ValueKey('quiet-hours-days'),
              icon: Icons.event_repeat_rounded,
              title: tr('Repeat'),
              subtitle: tr('Days quiet hours start'),
              value: quietDaysLabel(settings.quietDays),
              onTap: on
                  ? () => unawaited(_pickDays(context, ref, settings))
                  : null,
              showChevron: on,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Text(
            [
              tr(
                'Pick the days quiet hours start. A window that goes past midnight ends the next morning.',
              ),
              if (zone != null && zone.isNotEmpty)
                tr('Uses the time zone of your devices: {zone}.', {
                  'zone': zone,
                }),
            ].join(' '),
            key: const ValueKey('quiet-hours-footer'),
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.muted),
          ),
        ),
        const SizedBox(height: 12),
        SettingsGroup(
          header: tr('Still notify me about'),
          children: [
            SettingsRow.toggle(
              key: const ValueKey('quiet-hours-starred'),
              icon: Icons.star_border_rounded,
              tone: SettingsTone.warning,
              title: tr('Starred friends'),
              value: settings.allowStarred,
              onChanged: on
                  ? (value) => unawaited(
                      _save(
                        context,
                        ref,
                        settings.copyWith(allowStarred: value),
                      ),
                    )
                  : null,
            ),
            SettingsRow.toggle(
              key: const ValueKey('quiet-hours-mentions'),
              icon: Icons.alternate_email_rounded,
              title: tr('Mentions of me'),
              value: settings.allowMentions,
              onChanged: on
                  ? (value) => unawaited(
                      _save(
                        context,
                        ref,
                        settings.copyWith(allowMentions: value),
                      ),
                    )
                  : null,
            ),
            SettingsRow.toggle(
              key: const ValueKey('quiet-hours-calls'),
              icon: Icons.call_outlined,
              tone: SettingsTone.success,
              title: tr('Calls'),
              value: settings.allowCalls,
              onChanged: on
                  ? (value) => unawaited(
                      _save(context, ref, settings.copyWith(allowCalls: value)),
                    )
                  : null,
            ),
            SettingsRow(
              key: const ValueKey('quiet-hours-contacts'),
              icon: Icons.person_pin_circle_outlined,
              title: tr('Important contacts'),
              subtitle: tr('Friends you always hear from'),
              value: vipCount == 0
                  ? tr('None')
                  : vipCount == 1
                  ? tr('1 person')
                  : tr('{count} people', {'count': vipCount}),
              onTap: on
                  ? () => unawaited(_chooseContacts(context, ref, settings))
                  : null,
              showChevron: on,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          child: Text(
            tr(
              'Messages still arrive in Notifications. Do Not Disturb and muted chats stay quiet, even for these.',
            ),
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.muted),
          ),
        ),
      ],
    );
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    NotificationSettings next,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(notificationSettingsProvider.notifier)
          .saveQuietHours(next);
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(couldNotSaveText())));
    }
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref,
    NotificationSettings settings, {
    required bool start,
  }) async {
    final current = start ? settings.quietStart : settings.quietEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: start ? tr('Quiet hours start') : tr('Quiet hours end'),
    );
    if (picked == null || !context.mounted) {
      return;
    }
    final time = QuietTime(picked.hour, picked.minute);
    await _save(
      context,
      ref,
      start
          ? settings.copyWith(quietStart: time)
          : settings.copyWith(quietEnd: time),
    );
  }

  Future<void> _pickDays(
    BuildContext context,
    WidgetRef ref,
    NotificationSettings settings,
  ) async {
    final days = await showWeCordSheet<Set<int>>(
      context,
      title: tr('Repeat'),
      builder: (context, scroll) => QuietDaysSheet(initial: settings.quietDays),
    );
    if (days == null || !context.mounted) {
      return;
    }
    await _save(context, ref, settings.copyWith(quietDays: days));
  }

  Future<void> _chooseContacts(
    BuildContext context,
    WidgetRef ref,
    NotificationSettings settings,
  ) async {
    final friends = await ref.read(friendsProvider.future);
    if (!context.mounted) {
      return;
    }
    final chosen = await showWeCordSheet<Set<String>>(
      context,
      title: tr('Important contacts'),
      detents: const [0.6, 0.94],
      initialDetent: 0.94,
      builder: (context, scroll) => ImportantContactsSheet(
        friends: friends,
        initial: settings.vipUserIds,
        scroll: scroll,
      ),
    );
    if (chosen == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref
          .read(notificationSettingsProvider.notifier)
          .setImportantContacts(chosen);
    } on Object {
      messenger?.showSnackBar(SnackBar(content: Text(couldNotSaveText())));
    }
  }
}

/// "Every day", "Weekdays", "Weekends" or the days by name.
String quietDaysLabel(Set<int> days) {
  if (days.length == 7) {
    return tr('Every day');
  }
  if (days.length == 5 && days.containsAll(const {1, 2, 3, 4, 5})) {
    return tr('Weekdays');
  }
  if (days.length == 2 && days.containsAll(const {6, 7})) {
    return tr('Weekends');
  }
  return [
    for (var day = 1; day <= 7; day++)
      if (days.contains(day)) _shortDay(day),
  ].join(', ');
}

/// A sheet to choose the weekdays quiet hours start on; pops with them. At
/// least one stays chosen: no day would mean no quiet hours at all.
class QuietDaysSheet extends StatefulWidget {
  const QuietDaysSheet({required this.initial, super.key});

  final Set<int> initial;

  @override
  State<QuietDaysSheet> createState() => _QuietDaysSheetState();
}

class _QuietDaysSheetState extends State<QuietDaysSheet> {
  late final Set<int> _days = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroup(
              separatorIndent: 14,
              children: [
                for (var day = 1; day <= 7; day++)
                  SettingsRow(
                    key: ValueKey('quiet-day-$day'),
                    title: _longDay(day),
                    trailing: _days.contains(day)
                        ? Icon(Icons.check_rounded, size: 20, color: c.accent)
                        : const SizedBox(width: 20),
                    onTap: () => setState(() {
                      if (!_days.remove(day)) {
                        _days.add(day);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            WeCordButton(
              key: const ValueKey('quiet-days-done'),
              label: tr('Done'),
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: _days.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_days),
            ),
          ],
        ),
      ),
    );
  }
}

/// A sheet to choose the friends who are heard in quiet hours; pops with the
/// chosen ids.
class ImportantContactsSheet extends StatefulWidget {
  const ImportantContactsSheet({
    required this.friends,
    required this.initial,
    this.scroll,
    super.key,
  });

  final List<Profile> friends;
  final Set<String> initial;
  final ScrollController? scroll;

  @override
  State<ImportantContactsSheet> createState() => _ImportantContactsSheetState();
}

class _ImportantContactsSheetState extends State<ImportantContactsSheet> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              controller: widget.scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                  child: Text(
                    tr(
                      'You hear from these friends even in quiet hours. Only you can see this list.',
                    ),
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.4,
                      color: c.muted,
                    ),
                  ),
                ),
                FriendCheckList(
                  friends: widget.friends,
                  selected: _selected,
                  keyPrefix: 'quiet-contact',
                  emptyText: tr(
                    'Add friends first to choose important contacts.',
                  ),
                  onToggle: (friend) => setState(() {
                    if (!_selected.remove(friend.id)) {
                      _selected.add(friend.id);
                    }
                  }),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: WeCordButton(
              key: const ValueKey('quiet-contacts-done'),
              label: tr('Done'),
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_selected),
            ),
          ),
        ],
      ),
    );
  }
}
