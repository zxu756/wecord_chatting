import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/error_reports/error_reporting_hooks.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The account still owns a circle with other members in it.
class AccountOwnsCirclesException implements Exception {
  const AccountOwnsCirclesException();

  @override
  String toString() =>
      tr('Transfer ownership of your circles to another member first.');
}

abstract interface class AccountDeletionService {
  /// Deletes the signed-in account for good. Throws
  /// [AccountOwnsCirclesException] while it owns circles with members.
  Future<void> deleteAccount();
}

final accountDeletionServiceProvider = Provider<AccountDeletionService>((ref) {
  return SupabaseAccountDeletionService(ref.watch(supabaseClientProvider));
});

class SupabaseAccountDeletionService implements AccountDeletionService {
  const SupabaseAccountDeletionService(this._client);

  final SupabaseClient _client;

  @override
  Future<void> deleteAccount() async {
    try {
      await _client.functions.invoke('delete-account', body: const {});
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      if (error.status == 409 && code == 'owns_circles') {
        throw const AccountOwnsCirclesException();
      }
      rethrow;
    }
  }
}

/// Asks the user to type their username, deletes the account and signs
/// out. Returns whether the account was deleted.
Future<bool> confirmAndDeleteAccount(
  BuildContext context,
  WidgetRef ref, {
  required String username,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _DeleteAccountDialog(username: username),
  );
  if (confirmed != true || !context.mounted) {
    return false;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  // The login goes away: the sign-out that follows is not an anomaly.
  errorReporter.expectSignOut(within: const Duration(minutes: 2));
  try {
    await ref.read(accountDeletionServiceProvider).deleteAccount();
  } on AccountOwnsCirclesException catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text('$error')));
    return false;
  } catch (_) {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr('Could not delete your account. Try again.'))),
    );
    return false;
  }
  try {
    await ref.read(authRepositoryProvider).signOut();
  } catch (_) {
    // The login is already gone; the local session ends either way.
  }
  return true;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.username});

  final String username;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final matches = _controller.text.trim() == widget.username;
    final body = TextStyle(fontSize: 14, height: 1.45, color: c.muted);
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Delete account')),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            tr(
              'This deletes your login, profile, friends and avatar and takes '
              'you out of every circle and group. It cannot be undone.',
            ),
            style: body.copyWith(color: c.ink),
          ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Messages you sent stay where they are, shown as from '
              '"Deleted User". Circles you own with other members must be '
              'transferred first; circles with only you in them are deleted.',
            ),
            style: body,
          ),
          const SizedBox(height: 16),
          WeCordTextField(
            fieldKey: const ValueKey('delete-account-username'),
            controller: _controller,
            label: tr('Type {username} to confirm', {
              'username': widget.username,
            }),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        WeCordButton(
          label: tr('Cancel'),
          variant: WeCordButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        WeCordButton(
          key: const ValueKey('delete-account-confirm'),
          label: tr('Delete account'),
          variant: WeCordButtonVariant.danger,
          onPressed: matches
              ? () {
                  WeCordHaptics.heavy();
                  Navigator.of(context).pop(true);
                }
              : null,
        ),
      ],
    );
  }
}
