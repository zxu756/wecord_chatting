import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/shared/l10n/l10n.dart';

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
    final factor = ref.watch(twoFactorFactorProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Two-step verification'))),
      body: factor.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Could not load two-step verification.')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(twoFactorFactorProvider),
                  child: Text(tr('Try again')),
                ),
              ],
            ),
          ),
        ),
        data: (factorId) => Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error case final error?) ...[
                  Text(
                    error,
                    key: const ValueKey('two-factor-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (factorId != null)
                  ..._enabled(factorId)
                else if (_setup case final setup?)
                  ..._settingUp(setup)
                else
                  ..._disabled(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _enabled(String factorId) {
    final theme = Theme.of(context);
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.verified_user, color: theme.colorScheme.primary),
        title: Text(tr('Two-step verification is on')),
        subtitle: Text(
          tr(
            'Signing in asks for a code from your authenticator app after '
            'your password.',
          ),
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const ValueKey('two-factor-turn-off'),
          onPressed: _busy ? null : () => _turnOff(factorId),
          icon: const Icon(Icons.lock_open_outlined),
          label: Text(tr('Turn off')),
        ),
      ),
    ];
  }

  List<Widget> _disabled() {
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.phonelink_lock_outlined),
        title: Text(tr('Protect your account with a code')),
        subtitle: Text(
          tr(
            'After your password, signing in will also ask for a code from '
            'an authenticator app on your phone.',
          ),
        ),
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          key: const ValueKey('two-factor-set-up'),
          onPressed: _busy ? null : _startSetup,
          icon: const Icon(Icons.qr_code_2),
          label: Text(tr('Set up an authenticator app')),
        ),
      ),
    ];
  }

  List<Widget> _settingUp(TwoFactorSetup setup) {
    final theme = Theme.of(context);
    return [
      Text(
        tr('1. Scan this QR code with your authenticator app'),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      Center(
        child: Container(
          key: const ValueKey('two-factor-qr'),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            // Scanners need dark modules on a light background, in either
            // theme.
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
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
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: SelectableText(
              setup.secret,
              key: const ValueKey('two-factor-secret'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 1.5,
              ),
            ),
          ),
          IconButton(
            tooltip: tr('Copy key'),
            icon: const Icon(Icons.copy),
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
      const SizedBox(height: 24),
      Text(
        tr('2. Enter the 6-digit code it shows'),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('two-factor-setup-code'),
        controller: _code,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        maxLength: twoFactorCodeLength,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: tr('6-digit code'),
          counterText: '',
        ),
        onSubmitted: (_) => _confirmSetup(),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            key: const ValueKey('two-factor-confirm'),
            onPressed: _busy ? null : _confirmSetup,
            child: Text(tr('Turn on')),
          ),
          TextButton(
            onPressed: _busy ? null : _cancelSetup,
            child: Text(tr('Cancel')),
          ),
        ],
      ),
    ];
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
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Turn off two-step verification?')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              'Enter a code from your authenticator app to confirm. Signing '
              'in will then only need your password.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('two-factor-disable-code'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: twoFactorCodeLength,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: tr('6-digit code'),
              counterText: '',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('two-factor-disable-confirm'),
          onPressed: _submit,
          child: Text(tr('Turn off')),
        ),
      ],
    );
  }
}
