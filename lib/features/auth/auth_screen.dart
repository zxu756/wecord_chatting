import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_controller.dart';
import 'package:wecord/features/auth/auth_layout.dart';
import 'package:wecord/features/auth/passkey_sign_in_button.dart';
import 'package:wecord/features/auth/password_recovery.dart';
import 'package:wecord/features/legal/terms_checkbox.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  static const path = '/auth';

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  var _isCreatingAccount = false;
  var _acceptedTerms = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final c = context.tokens.colors;
    final creating = _isCreatingAccount;
    final title = creating ? tr('Create account') : tr('Sign in');
    final busy = state.isLoading;

    return AuthPage(
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              creating ? tr('Already have an account?') : tr('New here?'),
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ),
          const SizedBox(width: 4),
          AuthLink(
            key: const ValueKey('auth-toggle-mode'),
            label: creating ? tr('Sign in') : tr('Create account'),
            fontSize: 14,
            onPressed: busy ? null : _toggleMode,
          ),
        ],
      ),
      children: [
        const AuthAvatarCluster(),
        const SizedBox(height: 22),
        AuthHeading(
          title: creating
              ? tr('Make yourself\nat home.')
              : tr('Your friends,\nall in one place.'),
          subtitle: creating
              ? tr('Pick a username your friends can find you by.')
              : tr(
                  'Sign in to WeCord for direct messages, groups and circles.',
                ),
        ),
        const SizedBox(height: 26),
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (creating) ...[
                WeCordTextField(
                  fieldKey: const ValueKey('auth-username'),
                  controller: _usernameController,
                  label: tr('Username'),
                  onPaper: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newUsername],
                ),
                const SizedBox(height: 12),
                WeCordTextField(
                  fieldKey: const ValueKey('auth-display-name'),
                  controller: _displayNameController,
                  label: tr('Display name'),
                  onPaper: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                ),
                const SizedBox(height: 12),
              ],
              WeCordTextField(
                fieldKey: const ValueKey('auth-email'),
                controller: _emailController,
                label: tr('Email'),
                onPaper: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 12),
              WeCordTextField(
                fieldKey: const ValueKey('auth-password'),
                controller: _passwordController,
                label: tr('Password'),
                labelTrailing: creating
                    ? null
                    : AuthLink(
                        key: const ValueKey('auth-forgot-password'),
                        label: tr('Forgot password?'),
                        onPressed: busy ? null : _forgotPassword,
                      ),
                onPaper: true,
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: [
                  creating ? AutofillHints.newPassword : AutofillHints.password,
                ],
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        if (creating) ...[
          const SizedBox(height: 16),
          TermsAgreementCheckbox(
            key: const ValueKey('auth-accept-terms'),
            value: _acceptedTerms,
            onChanged: busy
                ? null
                : (value) => setState(() => _acceptedTerms = value),
          ),
        ],
        if (state.errorMessage != null) ...[
          const SizedBox(height: 16),
          AuthError(state.errorMessage!),
        ],
        const SizedBox(height: 22),
        WeCordButton(
          key: const ValueKey('auth-submit'),
          label: title,
          size: WeCordButtonSize.large,
          expand: true,
          loading: busy,
          onPressed: _submit,
        ),
        if (!creating) const PasskeySignInButton(),
      ],
    );
  }

  void _toggleMode() {
    setState(() {
      _isCreatingAccount = !_isCreatingAccount;
    });
  }

  Future<void> _forgotPassword() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) =>
          ForgotPasswordDialog(initialEmail: _emailController.text.trim()),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            tr('Check your email for a link to reset your password.'),
          ),
        ),
      );
    }
  }

  void _submit() {
    final controller = ref.read(authControllerProvider.notifier);

    if (_isCreatingAccount) {
      controller.signUp(
        _usernameController.text,
        _displayNameController.text,
        _emailController.text,
        _passwordController.text,
        acceptedTerms: _acceptedTerms,
      );
      return;
    }

    controller.signIn(_emailController.text, _passwordController.text);
  }
}

/// Asks for the account's email and sends it a password reset link.
/// Pops true once the email is sent.
class ForgotPasswordDialog extends ConsumerStatefulWidget {
  const ForgotPasswordDialog({this.initialEmail = '', super.key});

  final String initialEmail;

  @override
  ConsumerState<ForgotPasswordDialog> createState() =>
      _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends ConsumerState<ForgotPasswordDialog> {
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  var _sending = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = tr('Email is required.'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(passwordRecoveryRepositoryProvider)
          .sendPasswordReset(email);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = passwordRecoveryErrorMessage(error);
        });
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return AlertDialog(
      title: Text(tr('Reset your password')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                "Enter your account's email and we'll send you a link to set "
                'a new password.',
              ),
              style: TextStyle(fontSize: 15, color: c.muted),
            ),
            const SizedBox(height: 16),
            WeCordTextField(
              fieldKey: const ValueKey('forgot-password-email'),
              controller: _emailController,
              autofocus: true,
              label: tr('Email'),
              errorText: _error,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => _send(),
            ),
          ],
        ),
      ),
      actions: [
        WeCordButton(
          label: tr('Cancel'),
          variant: WeCordButtonVariant.secondary,
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
        ),
        WeCordButton(
          label: tr('Send link'),
          loading: _sending,
          onPressed: _send,
        ),
      ],
    );
  }
}
