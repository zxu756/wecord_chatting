import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/password_recovery.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Shown after the app was opened from a password reset link: the user is
/// signed in and chooses a new password (or keeps the old one).
class SetNewPasswordScreen extends ConsumerStatefulWidget {
  const SetNewPasswordScreen({super.key});

  static const path = '/reset-password';

  @override
  ConsumerState<SetNewPasswordScreen> createState() =>
      _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends ConsumerState<SetNewPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = newPasswordProblem(
      _passwordController.text,
      _confirmationController.text,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(passwordRecoveryRepositoryProvider)
          .updatePassword(_passwordController.text);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = passwordRecoveryErrorMessage(error);
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(tr('Your password was changed.'))));
    // The router leaves this page.
    ref.read(passwordRecoveryPendingProvider.notifier).finish();
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(
      authStateProvider.select((state) => state.valueOrNull?.email),
    );
    final title = tr('Set a new password');

    return Scaffold(
      appBar: AppBar(title: Text(title), automaticallyImplyLeading: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: AutofillGroup(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                if (email != null && email.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    tr('Choose a new password for {email}.', {'email': email}),
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  key: const ValueKey('new-password'),
                  controller: _passwordController,
                  decoration: InputDecoration(labelText: tr('New password')),
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('confirm-new-password'),
                  controller: _confirmationController,
                  decoration: InputDecoration(
                    labelText: tr('Confirm new password'),
                  ),
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: 16),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(tr('Save password')),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => ref
                            .read(passwordRecoveryPendingProvider.notifier)
                            .finish(),
                  child: Text(tr('Keep my current password')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
