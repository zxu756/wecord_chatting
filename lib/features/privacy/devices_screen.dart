import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/privacy/devices_repository.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings → Privacy & Safety → Devices.
void openDevices(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (context) => const DevicesScreen()));
}

/// "Just now", "5 minutes ago", "3 hours ago", "2 days ago" for [at].
String lastActiveLabel(DateTime at, {DateTime? now}) {
  final age = (now ?? DateTime.now()).toUtc().difference(at);
  if (age.inMinutes < 2) {
    return tr('Active just now');
  }
  if (age.inHours < 1) {
    return tr('Active {count} minutes ago', {'count': age.inMinutes});
  }
  if (age.inDays < 1) {
    return age.inHours == 1
        ? tr('Active 1 hour ago')
        : tr('Active {count} hours ago', {'count': age.inHours});
  }
  return age.inDays == 1
      ? tr('Active 1 day ago')
      : tr('Active {count} days ago', {'count': age.inDays});
}

IconData deviceIcon(String platform) => switch (platform) {
  'iOS' || 'Android' => Icons.smartphone_rounded,
  'Web' => Icons.language_rounded,
  _ => Icons.laptop_mac_rounded,
};

/// The devices signed in to the account: this one first, then the others
/// with when they were last active, each with a Sign out button, and
/// "Sign out of all other devices".
class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  final _busy = <String>{};
  var _signingOutOthers = false;

  Future<void> _revoke(DeviceSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Sign out {device}?', {'device': _name(session)})),
        content: Text(
          tr('It will be signed out the next time it connects to WeCord.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('device-sign-out-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Sign out')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy.add(session.sessionId));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(devicesRepositoryProvider).revoke(session.sessionId);
      ref.invalidate(deviceSessionsProvider);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not sign that device out.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy.remove(session.sessionId));
      }
    }
  }

  Future<void> _signOutOthers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Sign out of all other devices?')),
        content: Text(
          tr('Every device except this one will need to sign in again.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('devices-sign-out-others-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Sign out')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _signingOutOthers = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(devicesRepositoryProvider).signOutOthers();
      ref.invalidate(deviceSessionsProvider);
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not sign the other devices out.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _signingOutOthers = false);
      }
    }
  }

  String _name(DeviceSession session) {
    final title = session.title;
    return title.isEmpty ? tr('Unknown device') : title;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(deviceSessionsProvider);
    final c = context.tokens.colors;
    return SettingsPage(
      key: const ValueKey('devices-screen'),
      title: tr('Devices'),
      children: switch (sessions) {
        AsyncData(:final value) => _content(context, value),
        AsyncError() => [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  tr('Could not load your devices.'),
                  style: TextStyle(color: c.dangerText),
                ),
                const SizedBox(height: 12),
                WeCordButton(
                  label: tr('Try again'),
                  variant: WeCordButtonVariant.secondary,
                  onPressed: () => ref.invalidate(deviceSessionsProvider),
                ),
              ],
            ),
          ),
        ],
        _ => const [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      },
    );
  }

  List<Widget> _content(BuildContext context, List<DeviceSession> sessions) {
    final c = context.tokens.colors;
    final current = sessions.where((session) => session.isCurrent).firstOrNull;
    final others = [
      for (final session in sessions)
        if (!session.isCurrent) session,
    ];
    return [
      const SizedBox(height: 4),
      if (current != null)
        SettingsGroup(
          header: tr('This device'),
          children: [_DeviceRow(session: current, name: _name(current))],
        ),
      SettingsGroup(
        header: tr('Other devices'),
        footer: others.isEmpty
            ? null
            : tr(
                'Signed out devices need your password (and a code, if you use two-step verification) to come back.',
              ),
        children: [
          if (others.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                tr('No other devices are signed in.'),
                key: const ValueKey('devices-none'),
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
            ),
          for (final session in others)
            _DeviceRow(
              key: ValueKey('device-${session.sessionId}'),
              session: session,
              name: _name(session),
              busy: _busy.contains(session.sessionId),
              onSignOut: () => unawaited(_revoke(session)),
            ),
        ],
      ),
      if (others.isNotEmpty) ...[
        const SizedBox(height: 16),
        WeCordButton(
          key: const ValueKey('devices-sign-out-others'),
          label: tr('Sign out of all other devices'),
          variant: WeCordButtonVariant.danger,
          expand: true,
          loading: _signingOutOthers,
          onPressed: _signingOutOthers
              ? null
              : () => unawaited(_signOutOthers()),
        ),
      ],
    ];
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.session,
    required this.name,
    this.busy = false,
    this.onSignOut,
    super.key,
  });

  final DeviceSession session;
  final String name;
  final bool busy;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final details = [
      if (session.platform.isNotEmpty) session.platform,
      if (session.appVersion.isNotEmpty)
        tr('WeCord {version}', {'version': session.appVersion}),
      if (session.isCurrent)
        tr('Active now')
      else
        lastActiveLabel(session.lastActiveAt),
    ].join(' · ');
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SettingsIconTile(
              icon: deviceIcon(session.platform),
              tone: session.isCurrent
                  ? SettingsTone.success
                  : SettingsTone.neutral,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      details,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
            if (onSignOut != null) ...[
              const SizedBox(width: 8),
              WeCordButton(
                key: ValueKey('device-sign-out-${session.sessionId}'),
                label: tr('Sign out'),
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                loading: busy,
                onPressed: busy ? null : onSignOut,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
