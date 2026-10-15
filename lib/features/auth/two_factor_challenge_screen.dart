import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Shown after signing in to an account with two-step verification: the
/// user enters a code from their authenticator app before the app opens.
class TwoFactorChallengeScreen extends ConsumerStatefulWidget {
  const TwoFactorChallengeScreen({super.key});

  static const path = '/verify-sign-in';

  @override
  ConsumerState<TwoFactorChallengeScreen> createState() =>
      _TwoFactorChallengeScreenState();
}

class _TwoFactorChallengeScreenState
    extends ConsumerState<TwoFactorChallengeScreen> {
  final _code = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) {
      return;
    }
    final code = _code.text.trim();
    if (!isTwoFactorCode(code)) {
      setState(
        () => _error = tr('Enter the {count}-digit code.', {
          'count': twoFactorCodeLength,
        }),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(twoFactorRepositoryProvider).verifySignIn(code);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = twoFactorErrorMessage(error);
        });
        _code.clear();
      }
      return;
    }
    // The router leaves this page.
    ref.read(twoFactorPendingProvider.notifier).refresh();
  }

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signOut();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = ref.watch(
      authStateProvider.select((state) => state.valueOrNull?.email),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Two-step verification')),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.phonelink_lock_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                tr('Enter the code from your authenticator app'),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                email == null || email.isEmpty
                    ? tr('Your account asks for a code when you sign in.')
                    : tr('{email} asks for a code when signing in.', {
                        'email': email,
                      }),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextField(
                key: const ValueKey('two-factor-code'),
                controller: _code,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: twoFactorCodeLength,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: theme.textTheme.headlineSmall?.copyWith(
                  letterSpacing: 8,
                ),
                decoration: InputDecoration(
                  labelText: tr('6-digit code'),
                  counterText: '',
                  errorText: _error,
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('two-factor-verify'),
                onPressed: _busy ? null : _verify,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('Verify')),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _signOut,
                child: Text(tr('Sign out')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
