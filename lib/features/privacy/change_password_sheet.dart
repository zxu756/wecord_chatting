import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/password_recovery.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A sheet to choose a new password while signed in. Used after "Not me" on
/// a new-login alert, where the next step is changing the password.
Future<void> showChangePasswordSheet(BuildContext context) {
  return showWeCordSheet<void>(
    context,
    title: tr('Change password'),
    builder: (context, _) => const ChangePasswordForm(),
  );
}

class ChangePasswordForm extends ConsumerStatefulWidget {
  const ChangePasswordForm({super.key});

  @override
  ConsumerState<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends ConsumerState<ChangePasswordForm> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  var _saving = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = newPasswordProblem(_password.text, _confirmation.text);
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
          .updatePassword(_password.text);
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
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(
                'Choose a new password. Other devices stay signed in unless you sign them out.',
              ),
              style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
            ),
            const SizedBox(height: 16),
            AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  WeCordTextField(
                    fieldKey: const ValueKey('change-password-new'),
                    controller: _password,
                    label: tr('New password'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  WeCordTextField(
                    fieldKey: const ValueKey('change-password-confirm'),
                    controller: _confirmation,
                    label: tr('Confirm new password'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                  ),
                ],
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                key: const ValueKey('change-password-error'),
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ],
            const SizedBox(height: 18),
            WeCordButton(
              key: const ValueKey('change-password-save'),
              label: tr('Save password'),
              size: WeCordButtonSize.large,
              expand: true,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
