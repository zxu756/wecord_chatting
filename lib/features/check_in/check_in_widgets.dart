import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart' show ChatAvatar;
import 'package:wecord/features/check_in/check_in_models.dart';
import 'package:wecord/features/check_in/check_in_repository.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart'
    show chatImageProviderFactoryProvider;
import 'package:wecord/features/forms/form_models.dart' show FormImageAnswer;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Today 18/30".
String checkInTodayText(CheckInSnapshot check) {
  if (check.memberTotal <= 0) {
    return tr('Today {count}', {'count': check.todayCount});
  }
  return tr('Today {count}/{total}', {
    'count': check.todayCount,
    'total': check.memberTotal,
  });
}

/// "7-day streak".
String checkInStreakText(int days) => tr('{count}-day streak', {'count': days});

/// "You are on a 7-day streak", or what to do when there is none.
String checkInMyStreakText(CheckInSnapshot check) {
  if (check.myStreak > 0) {
    return tr('You are on a {count}-day streak', {'count': check.myStreak});
  }
  return tr('Check in today to start a streak');
}

/// The squircle with the check-in icon at the start of a card.
class CheckInIconTile extends StatelessWidget {
  const CheckInIconTile({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SettingsIconTile(
        icon: Icons.event_available_outlined,
        tone: SettingsTone.success,
        size: size,
      ),
    );
  }
}

/// A small pill: "Closed", "7-day streak".
class CheckInPill extends StatelessWidget {
  const CheckInPill({
    required this.text,
    this.icon,
    this.closed = false,
    this.hot = false,
    super.key,
  });

  final String text;
  final IconData? icon;
  final bool closed;

  /// A run worth showing off: warm, not red (red is for what needs doing).
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final foreground = closed ? c.muted : (hot ? c.successText : c.accentText);
    final fill = closed ? c.raised : (hot ? c.successSoft : c.accentSoft);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null || closed) ...[
            Icon(
              icon ?? Icons.lock_outline_rounded,
              size: 12,
              color: foreground,
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A picture of a check-in, read through a signed link (or from [bytes] when
/// just picked).
class CheckInPhotoThumb extends ConsumerWidget {
  const CheckInPhotoThumb({
    required this.image,
    this.bytes,
    this.size = 72,
    this.onTap,
    super.key,
  });

  final FormImageAnswer image;
  final Uint8List? bytes;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    Widget picture;
    if (bytes != null) {
      picture = Image.memory(
        bytes!,
        fit: BoxFit.cover,
        width: size,
        height: size,
      );
    } else {
      final url = ref.watch(checkInImageUrlProvider(image));
      picture = url.when(
        data: (link) => Image(
          image: ref.read(chatImageProviderFactoryProvider)(link),
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (_, _, _) => _placeholder(c, broken: true),
        ),
        loading: () => _placeholder(c),
        error: (_, _) => _placeholder(c, broken: true),
      );
    }
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(WeCordRadii.md),
      child: SizedBox(width: size, height: size, child: picture),
    );
    return Semantics(
      image: true,
      label: tr('Picture'),
      button: onTap != null,
      child: onTap == null
          ? thumb
          : WeCordPressable(
              onPressed: onTap,
              semanticLabel: tr('Open picture'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              builder: (context, states) => thumb,
            ),
    );
  }

  Widget _placeholder(WeCordPalette c, {bool broken = false}) {
    return Container(
      width: size,
      height: size,
      color: c.raised,
      alignment: Alignment.center,
      child: Icon(
        broken ? Icons.broken_image_outlined : Icons.image_outlined,
        color: c.faint,
        size: 22,
      ),
    );
  }
}

/// Opens a check-in picture full size.
Future<void> showCheckInPicture(BuildContext context, FormImageAnswer image) {
  return showDialog<void>(
    context: context,
    barrierColor: context.tokens.colors.scrim,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final url = ref.watch(checkInImageUrlProvider(image));
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
                child: url.when(
                  data: (link) => InteractiveViewer(
                    child: Image(
                      image: ref.read(chatImageProviderFactoryProvider)(link),
                      fit: BoxFit.contain,
                    ),
                  ),
                  loading: () => const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const SizedBox(
                    height: 200,
                    child: Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: WeCordIconButton(
                  tooltip: tr('Close'),
                  icon: Icons.close_rounded,
                  size: 36,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// One line of a day's list: who, when, their note and picture.
class CheckInEntryRow extends StatelessWidget {
  const CheckInEntryRow({
    required this.entry,
    required this.onOpenPicture,
    this.mine = false,
    super.key,
  });

  final CheckInEntry entry;
  final bool mine;
  final void Function(FormImageAnswer image) onOpenPicture;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final time = entry.createdAt == null
        ? null
        : TimeOfDay.fromDateTime(entry.createdAt!).format(context);
    final name = mine ? tr('You') : entry.name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: ChatAvatar(
              name: entry.name,
              avatarUrl: entry.avatarUrl,
              size: 36,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Who, when and what they wrote read as one line; the picture
                // below stays a button of its own.
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: c.ink,
                            ),
                          ),
                          if (time != null)
                            Text(
                              time,
                              style: TextStyle(fontSize: 12.5, color: c.subtle),
                            ),
                          if (entry.streak >= 2)
                            CheckInPill(
                              text: checkInStreakText(entry.streak),
                              icon: Icons.local_fire_department_outlined,
                              hot: true,
                            ),
                        ],
                      ),
                      if (entry.note.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            entry.note,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: c.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (entry.photo case final photo?)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: CheckInPhotoThumb(
                      image: photo,
                      size: 96,
                      onTap: () => onOpenPicture(photo),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The last five weeks as a grid of days (Monday first), the days the caller
/// checked in filled in. Small and quiet: a glance at the habit.
class CheckInCalendar extends StatelessWidget {
  const CheckInCalendar({
    required this.today,
    required this.days,
    this.weeks = 5,
    super.key,
  });

  final DateTime today;
  final Set<DateTime> days;
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final locale = MaterialLocalizations.of(context);
    final todayDate = DateTime(today.year, today.month, today.day);
    // The Monday of the first week shown.
    final monday = todayDate.subtract(
      Duration(days: todayDate.weekday - DateTime.monday),
    );
    final start = monday.subtract(Duration(days: 7 * (weeks - 1)));
    final done = {for (final d in days) DateTime(d.year, d.month, d.day)};
    final checked = <DateTime>[
      for (var i = 0; i < weeks * 7; i++) start.add(Duration(days: i)),
    ].where(done.contains).length;
    const dayCell = 26.0;
    return Semantics(
      container: true,
      label: tr('Your last {weeks} weeks: {count} days checked in', {
        'weeks': weeks,
        'count': checked,
      }),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: Center(
                      child: Text(
                        locale.narrowWeekdays[(DateTime.monday + d) % 7],
                        style: TextStyle(fontSize: 11.5, color: c.subtle),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var w = 0; w < weeks; w++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    for (var d = 0; d < 7; d++)
                      Expanded(
                        child: Center(
                          child: _Day(
                            size: dayCell,
                            date: start.add(Duration(days: w * 7 + d)),
                            today: todayDate,
                            done: done.contains(
                              start.add(Duration(days: w * 7 + d)),
                            ),
                          ),
                        ),
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

class _Day extends StatelessWidget {
  const _Day({
    required this.size,
    required this.date,
    required this.today,
    required this.done,
  });

  final double size;
  final DateTime date;
  final DateTime today;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final future = date.isAfter(today);
    final isToday = date == today;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? c.successSoft : (future ? Colors.transparent : c.raised),
        border: isToday ? Border.all(color: c.ink, width: 1.5) : null,
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 15, color: c.successText)
          : Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 11.5,
                color: future ? c.faint : c.muted,
              ),
            ),
    );
  }
}
