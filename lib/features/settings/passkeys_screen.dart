import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/passkeys.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/settings/account_security_widgets.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

void openPasskeys(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (context) => const PasskeysScreen()));
}

/// Settings → Passkeys: the passkeys on the account (name, when added, when
/// last used), add one on this device, rename or remove one.
class PasskeysScreen extends ConsumerStatefulWidget {
  const PasskeysScreen({super.key});

  @override
  ConsumerState<PasskeysScreen> createState() => _PasskeysScreenState();
}

class _PasskeysScreenState extends ConsumerState<PasskeysScreen> {
  var _busy = false;
  final _rowsBusy = <String>{};

  void _say(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _spin(String? rowId, bool on) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (rowId == null) {
        _busy = on;
      } else if (on) {
        _rowsBusy.add(rowId);
      } else {
        _rowsBusy.remove(rowId);
      }
    });
  }

  /// Runs [action] with the spinner on [rowId]'s row (the Add button when
  /// null). When the server wants a recent code from the authenticator app
  /// first (the account has two-step verification), the spinner stops, the
  /// code is asked for and [action] runs again.
  Future<bool> _guarded(Future<void> Function() action, {String? rowId}) async {
    _spin(rowId, true);
    try {
      await action();
      _spin(rowId, false);
      return true;
    } on PasskeyException catch (error) {
      _spin(rowId, false);
      if (error.failure != PasskeyFailure.needsAuthenticator) {
        final message = passkeyErrorMessage(error);
        if (message != null && mounted) {
          _say(message);
        }
        return false;
      }
    }
    if (!mounted) {
      return false;
    }
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AuthenticatorCodeDialog(
        title: tr('Confirm with your authenticator app'),
        body: tr(
          'Changing passkeys needs a current code from your authenticator '
          'app.',
        ),
        actionLabel: tr('Continue'),
      ),
    );
    if (code == null || !mounted) {
      return false;
    }
    _spin(rowId, true);
    try {
      await ref.read(twoFactorRepositoryProvider).verifySignIn(code);
      await action();
      _spin(rowId, false);
      return true;
    } catch (error) {
      _spin(rowId, false);
      if (mounted) {
        _say(
          error is PasskeyException
              ? passkeyErrorMessage(error) ?? ''
              : twoFactorErrorMessage(error),
        );
      }
      return false;
    }
  }

  Future<void> _add() async {
    final added = await _guarded(
      () => ref.read(passkeyRepositoryProvider).register(),
    );
    if (added && mounted) {
      ref.invalidate(passkeysProvider);
      _say(tr('Passkey added.'));
    }
  }

  Future<void> _rename(PasskeyInfo passkey) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: passkey.name),
    );
    if (name == null || name == passkey.name || !mounted) {
      return;
    }
    final done = await _guarded(
      () => ref.read(passkeyRepositoryProvider).rename(passkey.id, name),
      rowId: passkey.id,
    );
    if (done && mounted) {
      ref.invalidate(passkeysProvider);
    }
  }

  Future<void> _remove(PasskeyInfo passkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Remove {name}?', {'name': passkey.displayName})),
        content: Text(
          tr(
            'You will no longer be able to sign in with it. You can still '
            'sign in with your password.',
          ),
        ),
        actions: [
          WeCordButton(
            label: tr('Cancel'),
            variant: WeCordButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WeCordButton(
            key: const ValueKey('passkey-remove-confirm'),
            label: tr('Remove'),
            variant: WeCordButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final done = await _guarded(
      () => ref.read(passkeyRepositoryProvider).delete(passkey.id),
      rowId: passkey.id,
    );
    if (done && mounted) {
      ref.invalidate(passkeysProvider);
      _say(tr('Passkey removed.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final passkeys = ref.watch(passkeysProvider);
    final canAdd = ref.watch(passkeysAvailableProvider);
    return SettingsPage(
      key: const ValueKey('passkeys-screen'),
      title: tr('Passkeys'),
      maxWidth: 560,
      children: [
        const SizedBox(height: 12),
        SecurityCard(
          children: [
            SecurityIntro(
              icon: Icons.fingerprint_rounded,
              tone: SettingsTone.accent,
              title: tr('Sign in without a password'),
              body: tr(
                'A passkey lets you sign in with your face, fingerprint or '
                'device PIN. It stays on your device or in your password '
                "manager, and it can't be phished.",
              ),
            ),
            const SizedBox(height: 16),
            if (canAdd)
              Align(
                alignment: Alignment.centerLeft,
                child: WeCordButton(
                  key: const ValueKey('passkey-add'),
                  label: tr('Add a passkey'),
                  icon: Icons.add_rounded,
                  loading: _busy,
                  onPressed: _add,
                ),
              )
            else
              Text(
                tr(
                  'Passkeys can be added in the WeCord web app for now. '
                  'You can see and remove them here.',
                ),
                key: const ValueKey('passkey-web-only'),
                style: TextStyle(fontSize: 13.5, height: 1.45, color: c.muted),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ...switch (passkeys) {
          AsyncData(:final value) => [
            if (value.isEmpty)
              SecurityCard(
                children: [
                  Text(
                    tr('You have no passkeys yet.'),
                    key: const ValueKey('passkeys-empty'),
                    style: TextStyle(fontSize: 15, color: c.ink),
                  ),
                ],
              )
            else
              SettingsGroup(
                header: tr('Your passkeys'),
                footer: tr(
                  'An account with two-step verification still asks for its '
                  'code after a passkey.',
                ),
                children: [
                  for (final passkey in value)
                    _PasskeyRow(
                      passkey: passkey,
                      busy: _rowsBusy.contains(passkey.id),
                      onRename: () => _rename(passkey),
                      onRemove: () => _remove(passkey),
                    ),
                ],
              ),
          ],
          AsyncError() => [
            SecurityCard(
              children: [
                Text(
                  tr('Could not load your passkeys.'),
                  style: TextStyle(fontSize: 15, color: c.dangerText),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: WeCordButton(
                    label: tr('Try again'),
                    variant: WeCordButtonVariant.secondary,
                    onPressed: () => ref.invalidate(passkeysProvider),
                  ),
                ),
              ],
            ),
          ],
          _ => [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        },
      ],
    );
  }
}

class _PasskeyRow extends StatelessWidget {
  const _PasskeyRow({
    required this.passkey,
    required this.busy,
    required this.onRename,
    required this.onRemove,
  });

  final PasskeyInfo passkey;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final dates = MaterialLocalizations.of(context);
    final added = tr('Added {date}', {
      'date': dates.formatMediumDate(passkey.createdAt.toLocal()),
    });
    final used = passkey.lastUsedAt == null
        ? tr('Never used to sign in')
        : tr('Last used {date}', {
            'date': dates.formatMediumDate(passkey.lastUsedAt!.toLocal()),
          });
    return Padding(
      key: ValueKey('passkey-${passkey.id}'),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          const SettingsIconTile(icon: Icons.key_rounded, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passkey.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$added · $used',
                  style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            WeCordIconButton(
              key: ValueKey('passkey-rename-${passkey.id}'),
              icon: Icons.edit_outlined,
              tooltip: tr('Rename'),
              variant: WeCordButtonVariant.ghost,
              size: 40,
              iconSize: 18,
              onPressed: onRename,
            ),
            WeCordIconButton(
              key: ValueKey('passkey-remove-${passkey.id}'),
              icon: Icons.delete_outline_rounded,
              tooltip: tr('Remove'),
              variant: WeCordButtonVariant.ghost,
              size: 40,
              iconSize: 18,
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _name;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = tr('Enter a name.'));
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Rename passkey')),
      content: WeCordTextField(
        fieldKey: const ValueKey('passkey-name-field'),
        controller: _name,
        autofocus: true,
        hint: tr('Name'),
        errorText: _error,
        maxLength: 60,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        WeCordButton(
          label: tr('Cancel'),
          variant: WeCordButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        WeCordButton(
          key: const ValueKey('passkey-name-save'),
          label: tr('Save'),
          onPressed: _submit,
        ),
      ],
    );
  }
}
