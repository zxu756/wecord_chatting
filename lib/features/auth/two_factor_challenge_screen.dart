import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_layout.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

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
    final c = context.tokens.colors;
    final email = ref.watch(
      authStateProvider.select((state) => state.value?.email),
    );
    WeCordFieldBorder border(Color color, double width) => WeCordFieldBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.lg),
      borderSide: BorderSide(color: color, width: width),
    );
    return AuthPage(
      footer: Center(
        child: AuthLink(
          label: tr('Sign out'),
          fontSize: 14,
          onPressed: _busy ? null : _signOut,
        ),
      ),
      children: [
        const AuthIconTile(Icons.phonelink_lock_rounded),
        const SizedBox(height: 22),
        AuthHeading(
          compact: true,
          title: tr('Enter the code from your authenticator app'),
          subtitle: email == null || email.isEmpty
              ? tr('Your account asks for a code when you sign in.')
              : tr('{email} asks for a code when signing in.', {
                  'email': email,
                }),
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            tr('6-digit code'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.muted,
            ),
          ),
        ),
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
          style: theme.textTheme.headlineMedium?.copyWith(
            color: c.ink,
            letterSpacing: 10,
          ),
          decoration: InputDecoration(
            counterText: '',
            errorText: _error,
            filled: true,
            fillColor: c.panel,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            border: border(c.line, 1),
            enabledBorder: border(c.line, 1),
            disabledBorder: border(c.line, 1),
            focusedBorder: border(c.accent, 1.5),
            errorBorder: border(c.danger, 1.5),
            focusedErrorBorder: border(c.danger, 1.5),
          ),
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: 22),
        WeCordButton(
          key: const ValueKey('two-factor-verify'),
          label: tr('Verify'),
          size: WeCordButtonSize.large,
          expand: true,
          loading: _busy,
          onPressed: _verify,
        ),
      ],
    );
  }
}
