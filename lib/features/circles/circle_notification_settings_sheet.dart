import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_rail.dart';
import 'package:wecord/features/circles/circles_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_notification_settings.dart';

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
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
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
    final theme = Theme.of(context);
    final loaded = ref.watch(
      circleNotificationSettingsProvider(widget.circleId),
    );
    final settings = _saved ?? loaded.valueOrNull;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Notification settings'),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(widget.circleName, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (settings == null)
              loaded.hasError
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(tr('Could not load notification settings.')),
                    )
                  : const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    )
            else ...[
              _SectionLabel(tr('Mute circle')),
              ..._muteTiles(settings),
              const SizedBox(height: 8),
              _SectionLabel(tr('Notify me about')),
              RadioGroup<CircleNotificationLevel>(
                groupValue: settings.level,
                onChanged: (level) {
                  if (level == null || level == settings.level) {
                    return;
                  }
                  _save(settings, level: level);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (level, label) in const [
                      (CircleNotificationLevel.all, 'All messages'),
                      (CircleNotificationLevel.mentions, 'Only @mentions'),
                      (CircleNotificationLevel.none, 'Nothing'),
                    ])
                      RadioListTile<CircleNotificationLevel>(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr(label)),
                        value: level,
                        enabled: !_isSaving,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _muteTiles(CircleNotificationSettings settings) {
    final now = _now();
    if (settings.isMutedAt(now)) {
      return [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text(
            settings.isMutedIndefinitelyAt(now)
                ? tr('Muted until you turn it back on')
                : tr('Muted until {time}', {
                    'time': _formatMuteEnd(settings.mutedUntil!, now),
                  }),
          ),
          trailing: TextButton(
            onPressed: _isSaving ? null : () => _save(settings, unmute: true),
            child: Text(tr('Unmute')),
          ),
        ),
      ];
    }
    return [
      for (final (label, duration) in _muteOptions)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.notifications_paused_outlined),
          title: Text(tr(label)),
          enabled: !_isSaving,
          onTap: () => _save(settings, muteFor: duration),
        ),
    ];
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
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
