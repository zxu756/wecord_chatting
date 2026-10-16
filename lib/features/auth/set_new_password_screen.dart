import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_layout.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/password_recovery.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

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

    return AuthPage(
      footer: Center(
        child: AuthLink(
          label: tr('Keep my current password'),
          fontSize: 14,
          onPressed: _saving
              ? null
              : () => ref
                    .read(passwordRecoveryPendingProvider.notifier)
                    .finish(),
        ),
      ),
      children: [
        const AuthIconTile(Icons.key_rounded),
        const SizedBox(height: 22),
        AuthHeading(
          title: tr('Set a new password'),
          subtitle: email == null || email.isEmpty
              ? null
              : tr('Choose a new password for {email}.', {'email': email}),
        ),
        const SizedBox(height: 26),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WeCordTextField(
                fieldKey: const ValueKey('new-password'),
                controller: _passwordController,
                label: tr('New password'),
                onPaper: true,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              WeCordTextField(
                fieldKey: const ValueKey('confirm-new-password'),
                controller: _confirmationController,
                label: tr('Confirm new password'),
                onPaper: true,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
              ),
            ],
          ),
        ),
        if (_error case final error?) ...[
          const SizedBox(height: 16),
          AuthError(error),
        ],
        const SizedBox(height: 22),
        WeCordButton(
          label: tr('Save password'),
          size: WeCordButtonSize.large,
          expand: true,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
