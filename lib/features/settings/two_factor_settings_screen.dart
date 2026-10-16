import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

void openTwoFactorSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => const TwoFactorSettingsScreen(),
    ),
  );
}

/// Settings → Two-step verification: turn it on with an authenticator app
/// (QR code or secret, then a code), or off with a code.
class TwoFactorSettingsScreen extends ConsumerStatefulWidget {
  const TwoFactorSettingsScreen({super.key});

  @override
  ConsumerState<TwoFactorSettingsScreen> createState() =>
      _TwoFactorSettingsScreenState();
}

class _TwoFactorSettingsScreenState
    extends ConsumerState<TwoFactorSettingsScreen> {
  /// The authenticator being added, between the QR code and the code.
  TwoFactorSetup? _setup;
  final _code = TextEditingController();
  var _busy = false;
  String? _error;

  /// Kept for dispose, where ref can no longer be used.
  late final TwoFactorRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(twoFactorRepositoryProvider);
  }

  @override
  void dispose() {
    final setup = _setup;
    if (setup != null) {
      // Left without confirming: drop the half-added authenticator.
      _repository.cancelEnrollment(setup.factorId).ignore();
    }
    _code.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final setup = await ref.read(twoFactorRepositoryProvider).enroll();
      if (mounted) {
        setState(() {
          _setup = setup;
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = twoFactorErrorMessage(error);
        });
      }
    }
  }

  Future<void> _confirmSetup() async {
    final setup = _setup;
    if (setup == null || _busy) {
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
      await ref
          .read(twoFactorRepositoryProvider)
          .confirmEnrollment(factorId: setup.factorId, code: code);
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
    if (!mounted) {
      return;
    }
    setState(() {
      _setup = null;
      _busy = false;
    });
    _code.clear();
    ref.invalidate(twoFactorFactorProvider);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(tr('Two-step verification is on.'))),
    );
  }

  Future<void> _cancelSetup() async {
    final setup = _setup;
    setState(() {
      _setup = null;
      _error = null;
    });
    _code.clear();
    if (setup != null) {
      try {
        await ref
            .read(twoFactorRepositoryProvider)
            .cancelEnrollment(setup.factorId);
      } catch (_) {
        // A leftover unconfirmed authenticator is dropped on the next
        // setup.
      }
    }
  }

  Future<void> _turnOff(String factorId) async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => const _DisableDialog(),
    );
    if (code == null || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(twoFactorRepositoryProvider)
          .disable(factorId: factorId, code: code);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = twoFactorErrorMessage(error);
        });
      }
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    ref.invalidate(twoFactorFactorProvider);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(tr('Two-step verification is off.'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final factor = ref.watch(twoFactorFactorProvider);
    return SettingsPage(
      key: const ValueKey('two-factor-settings-screen'),
      title: tr('Two-step verification'),
      maxWidth: 560,
      children: [
        const SizedBox(height: 12),
        ...factor.when(
          loading: () => const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (error, stackTrace) => [
            _Card(
              children: [
                Text(
                  tr('Could not load two-step verification.'),
                  style: TextStyle(fontSize: 15, color: c.ink),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: WeCordButton(
                    label: tr('Try again'),
                    onPressed: () => ref.invalidate(twoFactorFactorProvider),
                  ),
                ),
              ],
            ),
          ],
          data: (factorId) => [
            if (_error case final error?)
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                child: Text(
                  error,
                  key: const ValueKey('two-factor-error'),
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ),
            if (factorId != null)
              _enabled(factorId)
            else if (_setup case final setup?)
              _settingUp(setup)
            else
              _disabled(),
          ],
        ),
      ],
    );
  }

  Widget _enabled(String factorId) {
    return _Card(
      children: [
        _Intro(
          icon: Icons.verified_user_outlined,
          tone: SettingsTone.success,
          title: tr('Two-step verification is on'),
          body: tr(
            'Signing in asks for a code from your authenticator app after '
            'your password.',
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: WeCordButton(
            key: const ValueKey('two-factor-turn-off'),
            label: tr('Turn off'),
            icon: Icons.lock_open_outlined,
            variant: WeCordButtonVariant.secondary,
            onPressed: _busy ? null : () => _turnOff(factorId),
          ),
        ),
      ],
    );
  }

  Widget _disabled() {
    return _Card(
      children: [
        _Intro(
          icon: Icons.phonelink_lock_outlined,
          tone: SettingsTone.accent,
          title: tr('Protect your account with a code'),
          body: tr(
            'After your password, signing in will also ask for a code from '
            'an authenticator app on your phone.',
          ),
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: WeCordButton(
            key: const ValueKey('two-factor-set-up'),
            label: tr('Set up an authenticator app'),
            icon: Icons.qr_code_2_rounded,
            loading: _busy,
            onPressed: _startSetup,
          ),
        ),
      ],
    );
  }

  Widget _settingUp(TwoFactorSetup setup) {
    final c = context.tokens.colors;
    final step = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    return _Card(
      children: [
        Text(
          tr('1. Scan this QR code with your authenticator app'),
          style: step,
        ),
        const SizedBox(height: 14),
        Center(
          child: Container(
            key: const ValueKey('two-factor-qr'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // Scanners need dark modules on a light background, in either
              // theme.
              color: Colors.white,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
              border: Border.all(color: c.line),
            ),
            child: QrImageView(
              data: setup.uri,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          tr("Can't scan it? Enter this key instead:"),
          style: TextStyle(fontSize: 14, color: c.muted),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          decoration: BoxDecoration(
            color: c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  setup.secret,
                  key: const ValueKey('two-factor-secret'),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: c.ink,
                  ),
                ),
              ),
              WeCordIconButton(
                icon: Icons.copy_rounded,
                tooltip: tr('Copy key'),
                variant: WeCordButtonVariant.ghost,
                size: 36,
                iconSize: 18,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: setup.secret));
                  if (mounted) {
                    ScaffoldMessenger.maybeOf(
                      context,
                    )?.showSnackBar(SnackBar(content: Text(tr('Copied'))));
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(tr('2. Enter the 6-digit code it shows'), style: step),
        const SizedBox(height: 10),
        WeCordTextField(
          fieldKey: const ValueKey('two-factor-setup-code'),
          controller: _code,
          enabled: !_busy,
          hint: tr('6-digit code'),
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(twoFactorCodeLength),
          ],
          onSubmitted: (_) => _confirmSetup(),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            WeCordButton(
              key: const ValueKey('two-factor-confirm'),
              label: tr('Turn on'),
              loading: _busy,
              onPressed: _confirmSetup,
            ),
            WeCordButton(
              label: tr('Cancel'),
              variant: WeCordButtonVariant.secondary,
              onPressed: _busy ? null : _cancelSetup,
            ),
          ],
        ),
      ],
    );
  }
}

/// A white card of the two-step verification page.
class _Card extends StatelessWidget {
  const _Card({required this.children});

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

/// An icon tile with a title and explanation.
class _Intro extends StatelessWidget {
  const _Intro({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
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

class _DisableDialog extends StatefulWidget {
  const _DisableDialog();

  @override
  State<_DisableDialog> createState() => _DisableDialogState();
}

class _DisableDialogState extends State<_DisableDialog> {
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
      title: Text(tr('Turn off two-step verification?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Enter a code from your authenticator app to confirm. Signing '
              'in will then only need your password.',
            ),
            style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
          ),
          const SizedBox(height: 14),
          WeCordTextField(
            fieldKey: const ValueKey('two-factor-disable-code'),
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
          key: const ValueKey('two-factor-disable-confirm'),
          label: tr('Turn off'),
          variant: WeCordButtonVariant.danger,
          onPressed: _submit,
        ),
      ],
    );
  }
}
