import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A white card on the account security pages (two-step verification,
/// recovery codes, passkeys, security log).
class SecurityCard extends StatelessWidget {
  const SecurityCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.tokens.colors.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// An icon tile with a title and an explanation.
class SecurityIntro extends StatelessWidget {
  const SecurityIntro({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final SettingsTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsIconTile(icon: icon, tone: tone, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Asks for a current code from the authenticator app (the step before
/// something that must not be done from a borrowed session). Pops the
/// six-digit code, or null.
class AuthenticatorCodeDialog extends StatefulWidget {
  const AuthenticatorCodeDialog({
    required this.title,
    required this.body,
    required this.actionLabel,
    this.danger = false,
    super.key,
  });

  final String title;
  final String body;
  final String actionLabel;
  final bool danger;

  @override
  State<AuthenticatorCodeDialog> createState() =>
      _AuthenticatorCodeDialogState();
}

class _AuthenticatorCodeDialogState extends State<AuthenticatorCodeDialog> {
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (!isTwoFactorCode(code)) {
      setState(
        () => _error = tr('Enter the {count}-digit code.', {
          'count': twoFactorCodeLength,
        }),
      );
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.body,
            style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
          ),
          const SizedBox(height: 14),
          WeCordTextField(
            fieldKey: const ValueKey('authenticator-code'),
            controller: _code,
            autofocus: true,
            hint: tr('6-digit code'),
            errorText: _error,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(twoFactorCodeLength),
            ],
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        WeCordButton(
          label: tr('Cancel'),
          variant: WeCordButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WeCordButton(
          key: const ValueKey('authenticator-code-confirm'),
          label: widget.actionLabel,
          variant: widget.danger
              ? WeCordButtonVariant.danger
              : WeCordButtonVariant.primary,
          onPressed: _submit,
        ),
      ],
    );
  }
}
