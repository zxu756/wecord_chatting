import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/inbox/inbox_card_shell.dart';
import 'package:wecord/features/privacy/change_password_sheet.dart';
import 'package:wecord/features/privacy/devices_screen.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the account's security record noted (G4).
enum AccountSecurityKind {
  recoveryCodesGenerated('recovery_codes_generated'),
  recoveryCodeUsed('recovery_code_used'),
  recoveryLocked('recovery_locked'),
  passkeyAdded('passkey_added'),
  passkeyRemoved('passkey_removed');

  const AccountSecurityKind(this.wire);

  final String wire;

  static AccountSecurityKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) {
        return kind;
      }
    }
    return null;
  }

  /// A change in how the account can be opened, which deserves a look from
  /// the person (all of them do, but a code used or a passkey added is the
  /// one that matters most if it was not them).
  bool get opensTheAccount => this == recoveryCodeUsed || this == passkeyAdded;
}

/// How an event was answered.
enum AccountSecurityAnswer {
  /// "It was me".
  confirmed('confirmed'),

  /// "Not me".
  denied('denied');

  const AccountSecurityAnswer(this.wire);

  final String wire;

  static AccountSecurityAnswer? fromWire(Object? value) {
    for (final answer in values) {
      if (answer.wire == value) {
        return answer;
      }
    }
    return null;
  }
}

class AccountSecurityEvent {
  const AccountSecurityEvent({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.passkeyName = '',
    this.answer,
  });

  /// Null for a kind this app does not know (a newer server): left out.
  static AccountSecurityEvent? tryParse(Map<String, dynamic> json) {
    final kind = AccountSecurityKind.fromWire(json['kind']);
    if (kind == null) {
      return null;
    }
    final detail = json['detail'];
    final name = detail is Map ? detail['name'] : null;
    return AccountSecurityEvent(
      id: json['id'] as String,
      kind: kind,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      passkeyName: name is String ? name.trim() : '',
      answer: AccountSecurityAnswer.fromWire(json['resolution']),
    );
  }

  final String id;
  final AccountSecurityKind kind;
  final DateTime createdAt;
  final String passkeyName;
  final AccountSecurityAnswer? answer;

  bool get isOpen => answer == null;

  String get headline => switch (kind) {
    AccountSecurityKind.recoveryCodesGenerated => tr(
      'New recovery codes were made',
    ),
    AccountSecurityKind.recoveryCodeUsed => tr(
      'A recovery code was used to sign in',
    ),
    AccountSecurityKind.recoveryLocked => tr('Too many wrong recovery codes'),
    AccountSecurityKind.passkeyAdded => tr(
      'A passkey was added to your account',
    ),
    AccountSecurityKind.passkeyRemoved => tr(
      'A passkey was removed from your account',
    ),
  };

  /// What changed, in a line.
  String get summary => switch (kind) {
    AccountSecurityKind.recoveryCodesGenerated => tr(
      'Your old recovery codes no longer work.',
    ),
    AccountSecurityKind.recoveryCodeUsed => tr(
      'Two-step verification was turned off.',
    ),
    AccountSecurityKind.recoveryLocked => tr(
      'Recovery is locked for 30 minutes.',
    ),
    AccountSecurityKind.passkeyAdded || AccountSecurityKind.passkeyRemoved =>
      passkeyName.isEmpty ? tr('Passkey') : passkeyName,
  };

  IconData get icon => switch (kind) {
    AccountSecurityKind.recoveryCodesGenerated ||
    AccountSecurityKind.recoveryCodeUsed ||
    AccountSecurityKind.recoveryLocked => Icons.key_rounded,
    AccountSecurityKind.passkeyAdded ||
    AccountSecurityKind.passkeyRemoved => Icons.fingerprint_rounded,
  };
}

abstract interface class AccountSecurityRepository {
  /// The record of the last 30 days, newest first.
  Future<List<AccountSecurityEvent>> list();

  Future<void> resolve(String eventId, AccountSecurityAnswer answer);
}

class SupabaseAccountSecurityRepository implements AccountSecurityRepository {
  const SupabaseAccountSecurityRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AccountSecurityEvent>> list() async {
    final rows = await _client.rpc<List<dynamic>>('list_my_security_events');
    return [
      for (final row in rows)
        ?AccountSecurityEvent.tryParse(row as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> resolve(String eventId, AccountSecurityAnswer answer) async {
    await _client.rpc<void>(
      'resolve_security_event',
      params: {'event_id': eventId, 'outcome': answer.wire},
    );
  }
}

class _UninitializedAccountSecurityRepository
    implements AccountSecurityRepository {
  const _UninitializedAccountSecurityRepository();

  @override
  Future<List<AccountSecurityEvent>> list() async => const [];

  @override
  Future<void> resolve(String eventId, AccountSecurityAnswer answer) async {}
}

final accountSecurityRepositoryProvider = Provider<AccountSecurityRepository>((
  ref,
) {
  try {
    return SupabaseAccountSecurityRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedAccountSecurityRepository();
  }
});

/// The record of the last 30 days.
final accountSecurityEventsProvider =
    FutureProvider.autoDispose<List<AccountSecurityEvent>>((ref) {
      return ref.watch(accountSecurityRepositoryProvider).list();
    });

/// The open events, and the ones answered in the last two days, for the
/// Security chip of Notifications.
final accountSecurityInboxProvider =
    Provider.autoDispose<List<AccountSecurityEvent>>((ref) {
      final events = ref.watch(accountSecurityEventsProvider).value;
      final recent = DateTime.now().toUtc().subtract(const Duration(days: 2));
      return [
        for (final event in events ?? const <AccountSecurityEvent>[])
          if (event.isOpen || event.createdAt.isAfter(recent)) event,
      ];
    });

/// How many events still wait for "It was me" or "Not me".
final accountSecurityOpenCountProvider = Provider.autoDispose<int>((ref) {
  return ref
      .watch(accountSecurityInboxProvider)
      .where((event) => event.isOpen)
      .length;
});

String _eventTime(DateTime at, DateTime now) {
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

/// A change to how the account opens, in Notifications → Security: "It was
/// me" closes it; "Not me" closes it and leads to the password and the
/// devices.
class AccountSecurityEventCard extends ConsumerStatefulWidget {
  const AccountSecurityEventCard({required this.event, super.key});

  final AccountSecurityEvent event;

  @override
  ConsumerState<AccountSecurityEventCard> createState() =>
      _AccountSecurityEventCardState();
}

class _AccountSecurityEventCardState
    extends ConsumerState<AccountSecurityEventCard> {
  var _busy = false;

  Future<void> _answer(AccountSecurityAnswer answer) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(accountSecurityRepositoryProvider)
          .resolve(widget.event.id, answer);
      ref.invalidate(accountSecurityEventsProvider);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not save your answer. Try again.'))),
        );
        setState(() => _busy = false);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    if (answer == AccountSecurityAnswer.denied) {
      await _offerHelp();
    }
  }

  Future<void> _offerHelp() async {
    final choice = await showDialog<_Help>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Secure your account')),
        content: Text(
          tr(
            'If this was not you, someone may know your password. Change it '
            'now and sign out the devices you do not recognize.',
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('security-event-help-later'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Later')),
          ),
          TextButton(
            key: const ValueKey('security-event-help-devices'),
            onPressed: () => Navigator.of(context).pop(_Help.devices),
            child: Text(tr('Review devices')),
          ),
          FilledButton(
            key: const ValueKey('security-event-help-password'),
            onPressed: () => Navigator.of(context).pop(_Help.password),
            child: Text(tr('Change password')),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    switch (choice) {
      case _Help.password:
        await showChangePasswordSheet(context);
      case _Help.devices:
        openDevices(context);
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final event = widget.event;
    final open = event.isOpen;
    final headline = switch (event.answer) {
      null => event.headline,
      AccountSecurityAnswer.confirmed => tr('You confirmed this change'),
      AccountSecurityAnswer.denied => tr('You said this was not you'),
    };
    return Semantics(
      container: true,
      label:
          '$headline. ${event.summary}. ${event.headline}. '
          '${spokenAge(event.createdAt)}',
      child: InboxCardShell(
        key: ValueKey('inbox-security-event-${event.id}'),
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
                        Icon(event.icon, size: 18, color: c.muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            open ? event.summary : event.headline,
                            maxLines: 6,
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
                          _eventTime(event.createdAt, DateTime.now()),
                          style: TextStyle(fontSize: 12.5, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  if (open) ...[
                    const SizedBox(height: 10),
                    Text(
                      event.kind.opensTheAccount
                          ? tr(
                              'Not you? Change your password and sign out '
                              'the devices you do not recognize.',
                            )
                          : tr('Not you? Change your password.'),
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
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Row(
                          children: [
                            Expanded(
                              child: WeCordButton(
                                key: const ValueKey('security-event-it-was-me'),
                                label: tr('It was me'),
                                size: WeCordButtonSize.small,
                                variant: WeCordButtonVariant.secondary,
                                expand: true,
                                onPressed: _busy
                                    ? null
                                    : () => _answer(
                                        AccountSecurityAnswer.confirmed,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: WeCordButton(
                                key: const ValueKey('security-event-not-me'),
                                label: tr('Not me'),
                                size: WeCordButtonSize.small,
                                variant: WeCordButtonVariant.danger,
                                expand: true,
                                onPressed: _busy
                                    ? null
                                    : () =>
                                          _answer(AccountSecurityAnswer.denied),
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

enum _Help { password, devices }
