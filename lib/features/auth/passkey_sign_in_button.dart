import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_layout.dart';
import 'package:wecord/features/auth/passkeys.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Sign in with a passkey" under the sign-in form: a face, a fingerprint
/// or a device PIN instead of the password. Nothing when this build does
/// not offer passkeys. A session from a passkey goes through the same
/// checks as a password one (an account with two-step verification still
/// asks for its code).
class PasskeySignInButton extends ConsumerStatefulWidget {
  const PasskeySignInButton({super.key});

  @override
  ConsumerState<PasskeySignInButton> createState() =>
      _PasskeySignInButtonState();
}

class _PasskeySignInButtonState extends ConsumerState<PasskeySignInButton> {
  var _busy = false;
  String? _error;

  Future<void> _signIn() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(passkeyRepositoryProvider).signIn();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = passkeyErrorMessage(error);
        });
      }
      return;
    }
    // The router leaves the page when the session arrives.
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(passkeysAvailableProvider)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        WeCordButton(
          key: const ValueKey('auth-passkey'),
          label: tr('Sign in with a passkey'),
          icon: Icons.fingerprint_rounded,
          variant: WeCordButtonVariant.secondary,
          size: WeCordButtonSize.large,
          expand: true,
          loading: _busy,
          onPressed: _signIn,
        ),
        if (_error != null) ...[const SizedBox(height: 12), AuthError(_error!)],
      ],
    );
  }
}
