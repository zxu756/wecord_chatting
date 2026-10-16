import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_channel_settings_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';
import 'package:wecord/shared/ui/ui.dart';

final circleNotificationSettingsProvider = FutureProvider.autoDispose
    .family<CircleNotificationSettings, String>((ref, circleId) {
      return ref
          .watch(circlesRepositoryProvider)
          .getNotificationSettings(circleId);
    });

void showCircleNotificationSettingsSheet(
  BuildContext context, {
  required String circleId,
  required String circleName,
}) {
  showCircleChannelPanel<void>(
    context,
    title: tr('Notification settings'),
    builder: (context) => CircleNotificationSettingsSheet(
      circleId: circleId,
      circleName: circleName,
    ),
  );
}

/// The current user's notification level and mute for one circle.
class CircleNotificationSettingsSheet extends ConsumerStatefulWidget {
  const CircleNotificationSettingsSheet({
    required this.circleId,
    required this.circleName,
    this.now,
    super.key,
  });

  final String circleId;
  final String circleName;
  final DateTime Function()? now;

  @override
  ConsumerState<CircleNotificationSettingsSheet> createState() =>
      _CircleNotificationSettingsSheetState();
}

class _CircleNotificationSettingsSheetState
    extends ConsumerState<CircleNotificationSettingsSheet> {
  static const _muteOptions = [
    ('For 15 minutes', Duration(minutes: 15)),
    ('For 1 hour', Duration(hours: 1)),
    ('For 8 hours', Duration(hours: 8)),
    ('For 24 hours', Duration(hours: 24)),
    ('Until I turn it back on', circleMuteIndefinitely),
  ];

  CircleNotificationSettings? _saved;
  var _isSaving = false;

  DateTime _now() => (widget.now ?? DateTime.now)().toUtc();

  Future<void> _save(
    CircleNotificationSettings current, {
    CircleNotificationLevel? level,
    Duration? muteFor,
    bool unmute = false,
  }) async {
    if (_isSaving) {
      return;
    }
    final mutedUntil = unmute
        ? null
        : muteFor != null
        ? _now().add(muteFor)
        : current.isMutedAt(_now())
        ? current.mutedUntil
        : null;
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final saved = await ref
          .read(circlesRepositoryProvider)
          .setNotificationSettings(
            circleId: widget.circleId,
            level: level ?? current.level,
            mutedUntil: mutedUntil,
          );
      if (!mounted) {
        return;
      }
      setState(() => _saved = saved);
      ref.invalidate(circleNotificationSettingsProvider(widget.circleId));
      ref.invalidate(conversationsProvider);
      ref.invalidate(circleSummariesProvider);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(tr('Could not save notification settings. Try again.')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final wide = circleWideLayout(context);
    final loaded = ref.watch(
      circleNotificationSettingsProvider(widget.circleId),
    );
    final settings = _saved ?? loaded.value;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        wide ? 20 : 12,
        0,
        wide ? 20 : 12,
        circleChannelPanelBottom(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              widget.circleName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ),
          if (settings == null)
            loaded.hasError
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 24,
                    ),
                    child: Text(tr('Could not load notification settings.')),
                  )
                : const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
          else ...[
            SettingsSectionHeader(tr('Mute circle')),
            SettingsGroup(color: c.well, children: _muteTiles(settings)),
            SettingsSectionHeader(tr('Notify me about')),
            SettingsGroup(
              color: c.well,
              children: [
                for (final (level, label, icon) in const [
                  (
                    CircleNotificationLevel.all,
                    'All messages',
                    Icons.notifications_active_outlined,
                  ),
                  (
                    CircleNotificationLevel.mentions,
                    'Only @mentions',
                    Icons.alternate_email_rounded,
                  ),
                  (
                    CircleNotificationLevel.none,
                    'Nothing',
                    Icons.notifications_none_rounded,
                  ),
                ])
                  SettingsRow(
                    key: ValueKey('circle-notify-${level.name}'),
                    icon: icon,
                    tone: settings.level == level
                        ? SettingsTone.accent
                        : SettingsTone.neutral,
                    title: tr(label),
                    showChevron: false,
                    trailing: _Check(selected: settings.level == level),
                    onTap: _isSaving || level == settings.level
                        ? null
                        : () => _save(settings, level: level),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _muteTiles(CircleNotificationSettings settings) {
    final now = _now();
    if (settings.isMutedAt(now)) {
      return [
        SettingsRow(
          icon: Icons.notifications_off_outlined,
          tone: SettingsTone.warning,
          title: settings.isMutedIndefinitelyAt(now)
              ? tr('Muted until you turn it back on')
              : tr('Muted until {time}', {
                  'time': _formatMuteEnd(settings.mutedUntil!, now),
                }),
          trailing: WeCordButton(
            label: tr('Unmute'),
            size: WeCordButtonSize.small,
            variant: WeCordButtonVariant.secondary,
            onPressed: _isSaving ? null : () => _save(settings, unmute: true),
          ),
        ),
      ];
    }
    return [
      for (final (label, duration) in _muteOptions)
        SettingsRow(
          icon: Icons.notifications_paused_outlined,
          title: tr(label),
          showChevron: false,
          onTap: _isSaving ? null : () => _save(settings, muteFor: duration),
        ),
    ];
  }
}

/// A round accent check for the chosen level, an empty ring otherwise.
class _Check extends StatelessWidget {
  const _Check({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return AnimatedContainer(
      duration: WeCordMotion.quick,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? c.accent : c.accent.withValues(alpha: 0),
        border: selected ? null : Border.all(color: c.track, width: 2),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 15, color: c.onAccent)
          : null,
    );
  }
}

String _formatMuteEnd(DateTime mutedUntil, DateTime now) {
  final local = mutedUntil.toLocal();
  final localNow = now.toLocal();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == localNow.year &&
      local.month == localNow.month &&
      local.day == localNow.day;
  return sameDay ? time : '${local.month}/${local.day} $time';
}
