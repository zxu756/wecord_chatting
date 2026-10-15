import 'package:flutter/material.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What an AutoMod alert message carries in its attachment
/// (`kind: automod_alert`, see `202610160020_automod.sql`).
class AutoModAlert {
  const AutoModAlert({
    required this.ruleName,
    required this.userLabel,
    required this.channelName,
    required this.content,
    required this.blocked,
    this.matched,
    this.timeoutSeconds,
  });

  static AutoModAlert? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null || json['kind'] != 'automod_alert') {
      return null;
    }
    return AutoModAlert(
      ruleName: json['rule_name'] as String? ?? '',
      userLabel: json['user_label'] as String? ?? '',
      channelName: json['channel_name'] as String? ?? '',
      content: json['content'] as String? ?? '',
      blocked: json['blocked'] == true,
      matched: json['matched'] as String?,
      timeoutSeconds: (json['timeout_seconds'] as num?)?.toInt(),
    );
  }

  final String ruleName;
  final String userLabel;
  final String channelName;

  /// The start of the message that matched.
  final String content;

  /// Whether the message was kept from being sent.
  final bool blocked;

  /// The keyword or pattern that matched, or what was counted.
  final String? matched;
  final int? timeoutSeconds;
}

/// An AutoMod alert in the alert channel: who, where, which rule, and the
/// message.
class AutoModAlertCard extends StatelessWidget {
  const AutoModAlertCard({required this.alert, super.key});

  final AutoModAlert alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = alert.blocked
        ? tr('AutoMod blocked a message from {name} in #{channel}', {
            'name': alert.userLabel,
            'channel': alert.channelName,
          })
        : tr('AutoMod flagged a message from {name} in #{channel}', {
            'name': alert.userLabel,
            'channel': alert.channelName,
          });
    final timeout = alert.timeoutSeconds;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: const ValueKey('automod-alert-card'),
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
                Icon(Icons.gpp_maybe_outlined, size: 18, color: colors.error),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
              ],
            ),
            if (alert.content.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                alert.content,
                style: theme.textTheme.bodyMedium,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              [
                tr('Rule: {rule}', {'rule': alert.ruleName}),
                if (alert.matched case final matched? when matched.isNotEmpty)
                  tr('Matched: {match}', {'match': matched}),
                if (timeout != null && timeout > 0)
                  tr('Timed out for {minutes} min', {
                    'minutes': (timeout / 60).ceil(),
                  }),
              ].join(' · '),
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
