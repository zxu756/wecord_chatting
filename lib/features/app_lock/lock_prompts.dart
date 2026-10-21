import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/app_lock_models.dart';
import 'package:wecord/features/app_lock/pin_pad.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/push/push_controller.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "0:25" or "14:59": how long is left of a wait.
String waitLabel(Duration left) {
  final seconds = left.inSeconds < 0 ? 0 : left.inSeconds;
  final minutes = seconds ~/ 60;
  return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// The words under the dots after a try.
String pinProblemText(PinResult result, {DateTime? now}) {
  if (result.isWaiting) {
    return tr('Too many tries. Try again in {time}.', {
      'time': waitLabel(result.waitUntil!.difference(now ?? DateTime.now())),
    });
  }
  return result.triesLeft == 1
      ? tr('Wrong PIN. 1 try left.')
      : tr('Wrong PIN. {count} tries left.', {'count': result.triesLeft});
}

/// A title, some words, the dots and the keypad, and the wait after too many
/// wrong tries. The one look of every PIN prompt.
class PinEntryView extends ConsumerStatefulWidget {
  const PinEntryView({
    required this.title,
    required this.onSubmit,
    this.subtitle,
    this.problem,
    this.waitUntil,
    this.footer,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Called with the six digits. Returns the words to show under the dots
  /// (a wrong try), or null.
  final Future<String?> Function(String pin) onSubmit;

  /// Words to show before any try (the last one's).
  final String? problem;

  /// While the person must wait, when the wait ends.
  final DateTime? waitUntil;
  final Widget? footer;

  @override
  ConsumerState<PinEntryView> createState() => _PinEntryViewState();
}

class _PinEntryViewState extends ConsumerState<PinEntryView> {
  String? _problem;
  DateTime? _waitUntil;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _problem = widget.problem;
    _waitUntil = widget.waitUntil;
    _tickIfWaiting();
  }

  @override
  void didUpdateWidget(PinEntryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.waitUntil != oldWidget.waitUntil) {
      _waitUntil = widget.waitUntil;
      _tickIfWaiting();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration? get _left {
    final until = _waitUntil;
    if (until == null) {
      return null;
    }
    final left = until.difference(ref.read(lockClockProvider)());
    return left.isNegative || left == Duration.zero ? null : left;
  }

  void _tickIfWaiting() {
    _ticker?.cancel();
    if (_left == null) {
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (_left == null) {
        _ticker?.cancel();
        setState(() {
          _waitUntil = null;
          _problem = null;
        });
      } else {
        setState(() {});
      }
    });
  }

  Future<void> _submit(String pin) async {
    final problem = await widget.onSubmit(pin);
    if (!mounted) {
      return;
    }
    setState(() => _problem = problem);
    final state = ref.read(appLockProvider);
    if (state.waitUntil != null) {
      _waitUntil = state.waitUntil;
      _tickIfWaiting();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final left = _left;
    final text = left != null
        ? tr('Too many tries. Try again in {time}.', {'time': waitLabel(left)})
        : _problem;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: c.ink,
            ),
          ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.4, color: c.muted),
          ),
        ],
        const SizedBox(height: 28),
        PinPad(enabled: left == null, error: text != null, onSubmit: _submit),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: text == null
              ? const SizedBox.shrink()
              : Semantics(
                  liveRegion: true,
                  child: Text(
                    text,
                    key: const ValueKey('pin-problem'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.dangerText,
                    ),
                  ),
                ),
        ),
        ?widget.footer,
      ],
    );
  }
}

/// "Forgot your PIN?": signing out is the way back, and it takes the lock
/// away from this device.
class ForgotPinButton extends ConsumerWidget {
  const ForgotPinButton({this.label, super.key});

  /// "Forgot your PIN?" by default.
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return WeCordButton(
      key: const ValueKey('forgot-pin'),
      label: label ?? tr('Forgot your PIN?'),
      variant: WeCordButtonVariant.ghost,
      size: WeCordButtonSize.small,
      onPressed: () => unawaited(signOutForForgottenPin(context, ref)),
    );
  }
}

/// Asks, then signs out. Signing out wipes the lock from this device (see
/// [AppLockController.wipe]), so signing in again starts without a PIN.
Future<void> signOutForForgottenPin(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      title: Text(tr('Sign out to reset the lock?')),
      content: Text(
        tr(
          'Signing out removes the PIN and the lock from this device. Sign in '
          'again to set a new one. Your chats stay safe on your account.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('forgot-pin-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(tr('Sign out')),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return;
  }
  await ref.read(appLockProvider.notifier).wipe();
  await stopPushForSignOut(ref);
  await ref.read(authRepositoryProvider).signOut();
}

/// A full-screen page around [child], on paper, with a close button.
class _PromptPage extends StatelessWidget {
  const _PromptPage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(WeCordSpace.gutter + 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: child,
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: WeCordIconButton(
                key: const ValueKey('pin-page-close'),
                icon: Icons.close_rounded,
                tooltip: tr('Close'),
                onPressed: () => Navigator.of(context).maybePop(false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the PIN; pops true when it is right.
class PinVerifyPage extends ConsumerWidget {
  const PinVerifyPage({this.title, this.subtitle, super.key});

  final String? title;
  final String? subtitle;

  static const pageKey = ValueKey('pin-verify-page');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appLockProvider);
    return _PromptPage(
      key: pageKey,
      child: PinEntryView(
        title: title ?? tr('Enter your PIN'),
        subtitle: subtitle,
        waitUntil: state.waitUntil,
        footer: const ForgotPinButton(),
        onSubmit: (pin) async {
          final result = ref.read(appLockProvider.notifier).checkPin(pin);
          if (result.ok) {
            Navigator.of(context).pop(true);
            return null;
          }
          return pinProblemText(result, now: ref.read(lockClockProvider)());
        },
      ),
    );
  }
}

/// Makes a new PIN: asks twice; pops true once it is set.
class PinSetupPage extends ConsumerStatefulWidget {
  const PinSetupPage({this.subtitle, super.key});

  final String? subtitle;

  static const pageKey = ValueKey('pin-setup-page');

  @override
  ConsumerState<PinSetupPage> createState() => _PinSetupPageState();
}

class _PinSetupPageState extends ConsumerState<PinSetupPage> {
  String? _first;
  String? _problem;

  @override
  Widget build(BuildContext context) {
    final again = _first != null;
    return _PromptPage(
      key: PinSetupPage.pageKey,
      child: PinEntryView(
        // A new entry for each step, so the keypad starts empty.
        key: ValueKey('pin-step-$again-$_problem'),
        title: again ? tr('Enter it again') : tr('Choose a PIN'),
        subtitle: again
            ? tr('Type the same {count} digits to confirm.', {
                'count': pinLength,
              })
            : widget.subtitle ??
                  tr('Pick {count} digits you will remember.', {
                    'count': pinLength,
                  }),
        problem: _problem,
        onSubmit: (pin) async {
          final first = _first;
          if (first == null) {
            setState(() {
              _first = pin;
              _problem = null;
            });
            return null;
          }
          if (first != pin) {
            setState(() {
              _first = null;
              _problem = tr('The two PINs did not match. Start again.');
            });
            return _problem;
          }
          await ref.read(appLockProvider.notifier).setPin(pin);
          if (context.mounted) {
            Navigator.of(context).pop(true);
          }
          return null;
        },
      ),
    );
  }
}

// ------------------------------------------------------------- the helpers

/// Makes sure the person has a way to prove who they are: the device's
/// (Face ID, Touch ID, the passcode), or else a PIN, which is asked for here.
/// False when they closed the PIN page.
Future<bool> ensureLockReady(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(appLockProvider.notifier);
  if (ref.read(appLockProvider).hasPin || await controller.systemAvailable()) {
    return true;
  }
  if (!context.mounted) {
    return false;
  }
  final made = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const PinSetupPage(),
    ),
  );
  return made ?? false;
}

/// Asks the person to prove who they are, with the PIN when they have one and
/// the device's prompt otherwise. True when they did.
Future<bool> verifyOwner(
  BuildContext context,
  WidgetRef ref, {
  String? reason,
  String? title,
}) async {
  final controller = ref.read(appLockProvider.notifier);
  if (ref.read(appLockProvider).hasPin) {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PinVerifyPage(title: title, subtitle: reason),
      ),
    );
    return ok ?? false;
  }
  final result = await controller.authenticateWithSystem(reason);
  return result == SystemAuthResult.success;
}
