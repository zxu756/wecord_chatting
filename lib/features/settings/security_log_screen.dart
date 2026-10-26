import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/privacy/account_security_events.dart';
import 'package:wecord/features/settings/account_security_widgets.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

void openSecurityLog(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const SecurityLogScreen()),
  );
}

/// Settings → Security log: what changed in how the account opens in the
/// last 30 days (recovery codes made or used, passkeys added or removed),
/// and how each was answered.
class SecurityLogScreen extends ConsumerWidget {
  const SecurityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final events = ref.watch(accountSecurityEventsProvider);
    return SettingsPage(
      key: const ValueKey('security-log-screen'),
      title: tr('Security log'),
      maxWidth: 560,
      children: [
        const SizedBox(height: 12),
        ...switch (events) {
          AsyncData(:final value) when value.isEmpty => [
            SecurityCard(
              children: [
                SecurityIntro(
                  icon: Icons.verified_user_outlined,
                  tone: SettingsTone.success,
                  title: tr('Nothing to report'),
                  body: tr(
                    'Changes to your recovery codes and passkeys in the last '
                    '30 days show up here.',
                  ),
                ),
              ],
            ),
          ],
          AsyncData(:final value) => [
            SettingsGroup(
              header: tr('Last 30 days'),
              footer: tr(
                'Each change also reached your devices as a notification.',
              ),
              children: [for (final event in value) _EventRow(event: event)],
            ),
          ],
          AsyncError() => [
            SecurityCard(
              children: [
                Text(
                  tr('Could not load the security log.'),
                  style: TextStyle(fontSize: 15, color: c.dangerText),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: WeCordButton(
                    label: tr('Try again'),
                    variant: WeCordButtonVariant.secondary,
                    onPressed: () =>
                        ref.invalidate(accountSecurityEventsProvider),
                  ),
                ),
              ],
            ),
          ],
          _ => [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        },
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final AccountSecurityEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final dates = MaterialLocalizations.of(context);
    final at = event.createdAt.toLocal();
    final when =
        '${dates.formatMediumDate(at)} '
        '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(at))}';
    final answer = switch (event.answer) {
      null => tr('Waiting for your answer'),
      AccountSecurityAnswer.confirmed => tr('You confirmed it'),
      AccountSecurityAnswer.denied => tr('You said it was not you'),
    };
    return Padding(
      key: ValueKey('security-log-${event.id}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsIconTile(
            icon: event.icon,
            tone: event.isOpen ? SettingsTone.warning : SettingsTone.neutral,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.headline,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  event.summary,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: c.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$when · $answer',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: event.isOpen ? c.warningText : c.subtle,
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
