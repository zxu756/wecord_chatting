import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_controller.dart';
import 'package:wecord/features/auth/password_recovery.dart';
import 'package:wecord/shared/l10n/l10n.dart';

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
    final title = _isCreatingAccount ? tr('Create account') : tr('Sign in');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),
              if (_isCreatingAccount) ...[
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(labelText: tr('Username')),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  decoration: InputDecoration(labelText: tr('Display name')),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: tr('Email')),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: tr('Password')),
                obscureText: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
              ),
              if (!_isCreatingAccount)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: state.isLoading ? null : _forgotPassword,
                    child: Text(tr('Forgot password?')),
                  ),
                ),
              if (state.errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: state.isLoading ? null : _submit,
                child: state.isLoading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(title),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: state.isLoading ? null : _toggleMode,
                child: Text(
                  _isCreatingAccount ? tr('Sign in') : tr('Create account'),
                ),
              ),
            ],
          ),
        ),
      ),
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
    return AlertDialog(
      title: Text(tr('Reset your password')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              "Enter your account's email and we'll send you a link to set "
              'a new password.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('forgot-password-email'),
            controller: _emailController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr('Email'),
              errorText: _error,
            ),
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            onSubmitted: (_) => _send(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: Text(tr('Send link')),
        ),
      ],
    );
  }
}
