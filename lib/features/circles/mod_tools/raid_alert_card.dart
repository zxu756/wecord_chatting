import 'package:flutter/material.dart';
import 'package:wecord/features/circles/mod_tools/raid_protection.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What the raid alert message carries in its attachment (`kind:
/// raid_alert`, see `202610250260_raid_detect.sql`).
class RaidAlert {
  const RaidAlert({
    required this.joins,
    required this.newAccounts,
    required this.hours,
    this.until,
  });

  static RaidAlert? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null || json['kind'] != 'raid_alert') {
      return null;
    }
    return RaidAlert(
      joins: (json['joins'] as num?)?.toInt() ?? 0,
      newAccounts: (json['new_accounts'] as num?)?.toInt() ?? 0,
      hours: (json['hours'] as num?)?.toInt() ?? 1,
      until: json['until'] is String
          ? DateTime.tryParse(json['until'] as String)
          : null,
    );
  }

  final int joins;
  final int newAccounts;
  final int hours;
  final DateTime? until;
}

/// A raid protection alert in the AutoMod alert channel: how many people
/// joined or asked in ten minutes, and what the circle did about it.
class RaidAlertCard extends StatelessWidget {
  const RaidAlertCard({required this.alert, super.key});

  final RaidAlert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final until = alert.until;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: const ValueKey('raid-alert-card'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: colors.error, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 18, color: colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Raid protection locked this circle'),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                '{count} people joined or asked to join within 10 minutes, '
                '{fresh} with a new account.',
                {'count': alert.joins, 'fresh': alert.newAccounts},
              ),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            Text(
              until == null
                  ? tr('Invites are paused and new people need approval.')
                  : tr(
                      'Invites are paused and new people need approval until '
                      '{time}. Nobody was removed.',
                      {'time': raidTimeLabel(until)},
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
