import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_layout.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/auth/recovery_codes.dart';
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
  final _recoveryCode = TextEditingController();
  var _busy = false;
  var _useRecoveryCode = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _recoveryCode.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() {
      _useRecoveryCode = !_useRecoveryCode;
      _error = null;
    });
  }

  /// Signs in past a lost authenticator app with a recovery code. The server
  /// turns two-step verification off for the account, so this page goes
  /// away once the session is refreshed.
  Future<void> _recover() async {
    if (_busy) {
      return;
    }
    final code = _recoveryCode.text.trim();
    if (!isRecoveryCode(code)) {
      setState(
        () => _error = tr('Enter the {count}-character recovery code.', {
          'count': recoveryCodeLength,
        }),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(recoveryCodesRepositoryProvider).recover(code);
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (error is RecoveryException &&
          error.failure == RecoveryFailure.notEnabled) {
        // Already off: the session was refreshed, so just let it through.
        ref.read(twoFactorPendingProvider.notifier).refresh();
        return;
      }
      setState(() {
        _busy = false;
        _error = recoveryErrorMessage(error);
      });
      _recoveryCode.clear();
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Two-step verification is off')),
        content: Text(
          tr(
            'You signed in with a recovery code, so two-step verification '
            'was turned off and your other codes no longer work. Turn it on '
            'again in Settings to keep your account safe.',
          ),
        ),
        actions: [
          WeCordButton(
            key: const ValueKey('two-factor-recovered-ok'),
            label: tr('Continue'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
    // The token in hand still lists the authenticator; a new one does not,
    // and the router leaves this page.
    if (mounted) {
      setState(() => _busy = true);
    }
    try {
      await ref.read(recoveryCodesRepositoryProvider).refreshSession();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = recoveryErrorMessage(error);
        });
      }
      return;
    }
    ref.read(twoFactorPendingProvider.notifier).refresh();
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
          title: _useRecoveryCode
              ? tr('Enter a recovery code')
              : tr('Enter the code from your authenticator app'),
          subtitle: _useRecoveryCode
              ? tr(
                  'Use one of the codes you saved when you turned on '
                  'two-step verification. It works once and turns '
                  'two-step verification off.',
                )
              : email == null || email.isEmpty
              ? tr('Your account asks for a code when you sign in.')
              : tr('{email} asks for a code when signing in.', {
                  'email': email,
                }),
        ),
        const SizedBox(height: 26),
        if (_useRecoveryCode)
          ..._recoveryFields(theme, c, border)
        else ...[
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
        const SizedBox(height: 18),
        Center(
          child: AuthLink(
            key: const ValueKey('two-factor-switch-mode'),
            label: _useRecoveryCode
                ? tr('Use my authenticator app instead')
                : tr('Lost your authenticator? Use a recovery code'),
            fontSize: 14,
            onPressed: _busy ? null : _switchMode,
          ),
        ),
      ],
    );
  }

  List<Widget> _recoveryFields(
    ThemeData theme,
    WeCordPalette c,
    WeCordFieldBorder Function(Color color, double width) border,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 6),
        child: Text(
          tr('Recovery code'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: c.muted,
          ),
        ),
      ),
      TextField(
        key: const ValueKey('recovery-code-field'),
        controller: _recoveryCode,
        autofocus: true,
        enabled: !_busy,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: const [RecoveryCodeFormatter()],
        style: theme.textTheme.titleLarge?.copyWith(
          color: c.ink,
          fontFamily: 'monospace',
          fontSize: 18,
          letterSpacing: 1.5,
        ),
        decoration: InputDecoration(
          hintText: recoveryCodeHint,
          errorText: _error,
          errorMaxLines: 3,
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
        onSubmitted: (_) => _recover(),
      ),
      const SizedBox(height: 22),
      WeCordButton(
        key: const ValueKey('recovery-code-submit'),
        label: tr('Verify'),
        size: WeCordButtonSize.large,
        expand: true,
        loading: _busy,
        onPressed: _recover,
      ),
    ];
  }
}
