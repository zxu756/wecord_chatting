import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/inbox/inbox_card_shell.dart';
import 'package:wecord/features/privacy/change_password_sheet.dart';
import 'package:wecord/features/privacy/devices_repository.dart';
import 'package:wecord/features/privacy/devices_screen.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How a new-login alert was closed.
enum LoginAlertResolution {
  /// "It was me".
  dismissed('dismissed'),

  /// "Not me": that session was signed out.
  revoked('revoked');

  const LoginAlertResolution(this.wire);

  final String wire;

  static LoginAlertResolution? fromWire(Object? value) {
    for (final resolution in values) {
      if (resolution.wire == value) {
        return resolution;
      }
    }
    return null;
  }
}

/// "A new device signed in": what the server recorded when a session
/// registered its device while the account had another. No address and no
/// location, as in Devices.
class LoginAlert {
  const LoginAlert({
    required this.id,
    required this.sessionId,
    required this.deviceName,
    required this.platform,
    required this.createdAt,
    this.resolution,
  });

  factory LoginAlert.fromJson(Map<String, dynamic> json) {
    return LoginAlert(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      deviceName: json['device_name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      resolution: LoginAlertResolution.fromWire(json['resolution']),
    );
  }

  final String id;

  /// The session that signed in; "Not me" signs it out.
  final String sessionId;
  final String deviceName;
  final String platform;
  final DateTime createdAt;
  final LoginAlertResolution? resolution;

  bool get isOpen => resolution == null;

  /// "Ada's MacBook (macOS)", the name alone, the platform alone, or empty.
  String get deviceLabel {
    final name = deviceName.trim();
    final platform = this.platform.trim();
    if (name.isEmpty) {
      return platform;
    }
    if (platform.isEmpty ||
        name.toLowerCase().contains(platform.toLowerCase())) {
      return name;
    }
    return '$name ($platform)';
  }
}

abstract interface class SecurityAlertsRepository {
  /// The alerts of the last 30 days, newest first.
  Future<List<LoginAlert>> list();

  Future<void> resolve(String alertId, LoginAlertResolution resolution);
}

class SupabaseSecurityAlertsRepository implements SecurityAlertsRepository {
  const SupabaseSecurityAlertsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<LoginAlert>> list() async {
    final rows = await _client.rpc<List<dynamic>>('list_my_login_alerts');
    return [
      for (final row in rows) LoginAlert.fromJson(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> resolve(String alertId, LoginAlertResolution resolution) async {
    await _client.rpc<void>(
      'resolve_login_alert',
      params: {'alert_id': alertId, 'outcome': resolution.wire},
    );
  }
}

class _UninitializedSecurityAlertsRepository
    implements SecurityAlertsRepository {
  const _UninitializedSecurityAlertsRepository();

  @override
  Future<List<LoginAlert>> list() async => const [];

  @override
  Future<void> resolve(String alertId, LoginAlertResolution resolution) async {}
}

final securityAlertsRepositoryProvider = Provider<SecurityAlertsRepository>((
  ref,
) {
  try {
    return SupabaseSecurityAlertsRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedSecurityAlertsRepository();
  }
});

/// The session id in a Supabase access token (its `session_id` claim), or
/// null when the token has none.
String? sessionIdOfToken(String? accessToken) {
  if (accessToken == null) {
    return null;
  }
  final parts = accessToken.split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    final payload = json.decode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final id = payload is Map ? payload['session_id'] : null;
    return id is String ? id : null;
  } on Object {
    return null;
  }
}

/// The session this device is signed in with (null if unknown).
final currentSessionIdProvider = Provider<String?>((ref) {
  try {
    return sessionIdOfToken(
      ref.watch(supabaseClientProvider).auth.currentSession?.accessToken,
    );
  } on ProviderException {
    return null;
  }
});

/// The open alerts, and the ones closed in the last two days, for the
/// Security card in Notifications. The alert about this very device is
/// left out: it is the one that signed in.
final securityAlertsProvider = FutureProvider.autoDispose<List<LoginAlert>>((
  ref,
) async {
  final alerts = await ref.watch(securityAlertsRepositoryProvider).list();
  final current = ref.watch(currentSessionIdProvider);
  final recent = DateTime.now().toUtc().subtract(const Duration(days: 2));
  return [
    for (final alert in alerts)
      if (alert.sessionId != current &&
          (alert.isOpen || alert.createdAt.isAfter(recent)))
        alert,
  ];
});

/// How many alerts still wait for "It was me" or "Not me".
final securityAlertsOpenCountProvider = Provider.autoDispose<int>((ref) {
  return ref
          .watch(securityAlertsProvider)
          .value
          ?.where((alert) => alert.isOpen)
          .length ??
      0;
});

String _alertTime(DateTime at, DateTime now) {
  final local = at.toLocal();
  final clock =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final today =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  return today ? clock : '${local.month}/${local.day} $clock';
}

/// "New sign-in to your account": the device, the platform and the time,
/// with "It was me" and "Not me". Not me signs that session out (the
/// Devices sign-out path, the sessions Edge Function) and leads to changing
/// the password.
class SecurityAlertCard extends ConsumerStatefulWidget {
  const SecurityAlertCard({required this.alert, super.key});

  final LoginAlert alert;

  @override
  ConsumerState<SecurityAlertCard> createState() => _SecurityAlertCardState();
}

class _SecurityAlertCardState extends ConsumerState<SecurityAlertCard> {
  var _busy = false;

  Future<void> _itWasMe() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(securityAlertsRepositoryProvider)
          .resolve(widget.alert.id, LoginAlertResolution.dismissed);
      ref.invalidate(securityAlertsProvider);
    } catch (_) {
      _failed();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _notMe() async {
    setState(() => _busy = true);
    try {
      try {
        await ref
            .read(devicesRepositoryProvider)
            .revoke(widget.alert.sessionId);
      } on FunctionException catch (error) {
        // Already signed out (it expired, or another device did it).
        if (error.status != 404) {
          rethrow;
        }
      }
      await ref
          .read(securityAlertsRepositoryProvider)
          .resolve(widget.alert.id, LoginAlertResolution.revoked);
      ref
        ..invalidate(securityAlertsProvider)
        ..invalidate(deviceSessionsProvider);
    } catch (_) {
      _failed();
      if (mounted) {
        setState(() => _busy = false);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    await _offerPasswordChange();
  }

  void _failed() {
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(tr('Could not sign that device out.'))),
      );
    }
  }

  Future<void> _offerPasswordChange() async {
    final change = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('That device was signed out')),
        content: Text(
          tr(
            'If you did not sign in, someone may know your password. Change it now.',
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('security-password-later'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Later')),
          ),
          FilledButton(
            key: const ValueKey('security-password-change'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Change password')),
          ),
        ],
      ),
    );
    if (change == true && mounted) {
      await showChangePasswordSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final alert = widget.alert;
    final open = alert.isOpen;
    final label = alert.deviceLabel.isEmpty
        ? tr('Unknown device')
        : alert.deviceLabel;
    final time = _alertTime(alert.createdAt, DateTime.now());
    final headline = switch (alert.resolution) {
      null => tr('New sign-in to your account'),
      LoginAlertResolution.dismissed => tr('You confirmed this sign-in'),
      LoginAlertResolution.revoked => tr('You signed that device out'),
    };
    return Semantics(
      container: true,
      label: '$headline. $label. ${spokenAge(alert.createdAt)}',
      child: InboxCardShell(
        key: ValueKey('inbox-security-${alert.id}'),
        highlighted: open,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsIconTile(
              icon: open ? Icons.shield_outlined : Icons.verified_user_outlined,
              tone: open ? SettingsTone.warning : SettingsTone.neutral,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: c.well,
                      borderRadius: BorderRadius.circular(WeCordRadii.md),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          deviceIcon(alert.platform),
                          size: 18,
                          color: c.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: c.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          time,
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  if (open) ...[
                    const SizedBox(height: 10),
                    Text(
                      tr(
                        'Not you? Sign that device out and change your password.',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: ConstrainedBox(
                        // Wide windows keep the two pills at phone size.
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Row(
                          children: [
                            Expanded(
                              child: WeCordButton(
                                key: const ValueKey('security-it-was-me'),
                                label: tr('It was me'),
                                size: WeCordButtonSize.small,
                                variant: WeCordButtonVariant.secondary,
                                expand: true,
                                onPressed: _busy ? null : _itWasMe,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: WeCordButton(
                                key: const ValueKey('security-not-me'),
                                label: tr('Not me'),
                                size: WeCordButtonSize.small,
                                variant: WeCordButtonVariant.danger,
                                expand: true,
                                onPressed: _busy ? null : _notMe,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
