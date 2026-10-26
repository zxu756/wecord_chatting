import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wecord/features/auth/recovery_codes.dart';
import 'package:wecord/features/auth/two_factor.dart';
import 'package:wecord/features/settings/account_security_widgets.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Makes a new set of recovery codes and shows it.
///
/// [askForCode]: first ask for a current code from the authenticator app
/// (the server only makes codes for a session that just passed one). Right
/// after turning two-step verification on it already has, so that screen
/// passes false.
Future<void> makeRecoveryCodes(
  BuildContext context,
  WidgetRef ref, {
  bool askForCode = true,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (askForCode) {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AuthenticatorCodeDialog(
        title: tr('Make new recovery codes?'),
        body: tr(
          'Your current codes stop working. Enter a code from your '
          'authenticator app to continue.',
        ),
        actionLabel: tr('Make new codes'),
      ),
    );
    if (code == null || !context.mounted) {
      return;
    }
    try {
      await ref.read(twoFactorRepositoryProvider).verifySignIn(code);
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text(twoFactorErrorMessage(error))),
      );
      return;
    }
  }
  final List<String> codes;
  try {
    codes = await ref.read(recoveryCodesRepositoryProvider).generate();
  } catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text(recoveryErrorMessage(error))),
    );
    ref.invalidate(recoveryStatusProvider);
    return;
  }
  ref.invalidate(recoveryStatusProvider);
  if (!context.mounted) {
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => RecoveryCodesScreen(codes: codes),
    ),
  );
}

/// The new codes, shown once, to copy or share and to confirm they are
/// saved. Leaving without confirming asks first: they cannot be shown again.
class RecoveryCodesScreen extends StatefulWidget {
  const RecoveryCodesScreen({required this.codes, super.key});

  final List<String> codes;

  @override
  State<RecoveryCodesScreen> createState() => _RecoveryCodesScreenState();
}

class _RecoveryCodesScreenState extends State<RecoveryCodesScreen> {
  var _saved = false;

  String get _text =>
      '${tr('WeCord recovery codes')}\n'
      '${widget.codes.join('\n')}\n\n'
      '${tr('Each code works once. Keep them somewhere safe.')}';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text));
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(tr('Copied'))));
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: _text, subject: tr('WeCord recovery codes')),
      );
    } on Object {
      // The sheet could not open; Copy still works.
    }
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Leave without saving?')),
        content: Text(
          tr(
            "These codes can't be shown again. Without them, losing your "
            'authenticator app could lock you out.',
          ),
        ),
        actions: [
          WeCordButton(
            key: const ValueKey('recovery-codes-stay'),
            label: tr('Stay'),
            variant: WeCordButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          WeCordButton(
            key: const ValueKey('recovery-codes-leave'),
            label: tr('Leave'),
            variant: WeCordButtonVariant.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return leave == true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return PopScope(
      canPop: _saved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        final navigator = Navigator.of(context);
        if (await _confirmLeave()) {
          navigator.pop();
        }
      },
      child: SettingsPage(
        key: const ValueKey('recovery-codes-screen'),
        title: tr('Recovery codes'),
        maxWidth: 560,
        children: [
          const SizedBox(height: 12),
          SecurityCard(
            children: [
              SecurityIntro(
                icon: Icons.key_rounded,
                tone: SettingsTone.warning,
                title: tr('Save these codes now'),
                body: tr(
                  'If you lose your authenticator app, one of these codes '
                  'gets you back into your account. Each works once. They '
                  "are shown only now, and WeCord can't show them again.",
                ),
              ),
              const SizedBox(height: 16),
              Container(
                key: const ValueKey('recovery-codes-list'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: c.well,
                  borderRadius: BorderRadius.circular(WeCordRadii.md),
                ),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 10,
                  children: [
                    for (final (index, code) in widget.codes.indexed)
                      Semantics(
                        label: tr('Code {number}: {code}', {
                          'number': index + 1,
                          'code': code.split('').join(' '),
                        }),
                        excludeSemantics: true,
                        child: SelectableText(
                          code,
                          key: ValueKey('recovery-code-$index'),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: c.ink,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  WeCordButton(
                    key: const ValueKey('recovery-codes-copy'),
                    label: tr('Copy'),
                    icon: Icons.copy_rounded,
                    variant: WeCordButtonVariant.secondary,
                    onPressed: _copy,
                  ),
                  WeCordButton(
                    key: const ValueKey('recovery-codes-share'),
                    label: tr('Share'),
                    icon: Icons.ios_share_rounded,
                    variant: WeCordButtonVariant.secondary,
                    onPressed: _share,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  key: const ValueKey('recovery-codes-saved'),
                  value: _saved,
                  onChanged: (value) => setState(() => _saved = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(WeCordRadii.md),
                  ),
                  title: Text(
                    tr('I saved these codes somewhere safe'),
                    style: TextStyle(fontSize: 14.5, color: c.ink),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              WeCordButton(
                key: const ValueKey('recovery-codes-done'),
                label: tr('Done'),
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: _saved ? () => Navigator.of(context).pop() : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Recovery codes" on the two-step verification page: how many are left,
/// and a button to make a new set.
class RecoveryCodesCard extends ConsumerWidget {
  const RecoveryCodesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final status = ref.watch(recoveryStatusProvider);
    final loaded = status.asData?.value;
    final tone = switch (loaded) {
      null => SettingsTone.neutral,
      RecoveryStatus(hasCodes: false) => SettingsTone.warning,
      RecoveryStatus(runningLow: true) => SettingsTone.warning,
      _ => SettingsTone.success,
    };
    final body = switch (status) {
      AsyncData(:final value) when !value.hasCodes => tr(
        'You have no recovery codes. Make a set so you can get back in if '
        'you lose your authenticator app.',
      ),
      AsyncData(:final value) when value.remaining == 0 => tr(
        'You have used all of your codes. Make a new set.',
      ),
      AsyncData(:final value) when value.runningLow =>
        value.remaining == 1
            ? tr('Only 1 of {total} codes is left. Make a new set.', {
                'total': value.total,
              })
            : tr('Only {count} of {total} codes are left. Make a new set.', {
                'count': value.remaining,
                'total': value.total,
              }),
      AsyncData(:final value) => tr(
        '{count} of {total} codes are left. Each works once.',
        {'count': value.remaining, 'total': value.total},
      ),
      AsyncError() => tr('Could not load your recovery codes.'),
      _ => tr('Checking your recovery codes…'),
    };
    final hasCodes = loaded?.hasCodes ?? false;
    return SecurityCard(
      children: [
        SecurityIntro(
          icon: Icons.key_rounded,
          tone: tone,
          title: tr('Recovery codes'),
          body: body,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: status.hasError
              ? WeCordButton(
                  key: const ValueKey('recovery-codes-retry'),
                  label: tr('Try again'),
                  variant: WeCordButtonVariant.secondary,
                  onPressed: () => ref.invalidate(recoveryStatusProvider),
                )
              : WeCordButton(
                  key: const ValueKey('recovery-codes-make'),
                  label: hasCodes
                      ? tr('Make new codes')
                      : tr('Make recovery codes'),
                  icon: Icons.key_rounded,
                  variant: hasCodes && !(loaded?.runningLow ?? false)
                      ? WeCordButtonVariant.secondary
                      : WeCordButtonVariant.primary,
                  onPressed: loaded == null
                      ? null
                      : () => makeRecoveryCodes(context, ref),
                ),
        ),
        if (loaded?.lockedUntil case final until?)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              tr(
                'Recovery is locked for a while because of wrong codes '
                '(until {time}).',
                {'time': _clock(until.toLocal())},
              ),
              key: const ValueKey('recovery-locked-note'),
              style: TextStyle(fontSize: 13, height: 1.4, color: c.warningText),
            ),
          ),
      ],
    );
  }

  String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
