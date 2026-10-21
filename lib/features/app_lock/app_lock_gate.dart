import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/app_lock_models.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/app_lock/lock_prompts.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Covers the app with [AppLockScreen] while it is locked, and watches the
/// app go out of sight and come back to decide when to lock it. Sits in
/// `MaterialApp.builder`, above the router, so it covers every page. The app
/// underneath stays alive (a draft being typed is still there when the person
/// unlocks), but it is not drawn, not read by screen readers and takes no
/// input.
///
/// It also keeps the chat lock honest: after the app was out of sight for a
/// minute every locked chat asks again, and hidden chats hide again; and on
/// iPhone the app switcher shows a plain cover instead of the last screen.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  DateTime? _awayAt;
  var _inactive = false;

  /// Returning from the app switcher or a system sheet in under this long
  /// does not count as coming back.
  static const _realReturn = Duration(seconds: 1);

  bool get _isApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(appLockProvider.notifier);
    final now = ref.read(lockClockProvider)();
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _markAway(controller, now);
      case AppLifecycleState.inactive:
        // On a computer the window losing focus is leaving; on a phone it is
        // the app switcher or a system sheet, which only gets the cover.
        if (_isDesktop) {
          _markAway(controller, now);
        }
        if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
          setState(() => _inactive = true);
        }
      case AppLifecycleState.resumed:
        if (_inactive) {
          setState(() => _inactive = false);
        }
        _returned(controller, now);
      case AppLifecycleState.detached:
        break;
    }
  }

  void _markAway(AppLockController controller, DateTime now) {
    if (controller.isAuthenticating) {
      return;
    }
    controller.appLeft();
    _awayAt ??= now;
  }

  void _returned(AppLockController controller, DateTime now) {
    final away = _awayAt;
    _awayAt = null;
    controller.appReturned();
    if (away == null) {
      return;
    }
    final awayFor = now.difference(away);
    if (awayFor >= chatUnlockGrace) {
      ref.read(chatLockProvider.notifier).relockAll();
    } else {
      // Short trips keep the chats open but not the revealed secret ones.
    }
    if (awayFor >= _realReturn) {
      unawaited(ref.read(chatLockProvider.notifier).refresh());
      final lock = ref.read(appLockProvider);
      if (lock.enabled && lock.locked && lock.method == LockMethod.system) {
        unawaited(controller.unlockWithSystem());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    // The sign-in page is never covered: there is nothing to protect, and
    // signing out is how a forgotten PIN is dealt with.
    final signedOut = ref.watch(
      authStateProvider.select(
        (state) => state.hasValue && state.value == null,
      ),
    );
    final covered = lock.enabled && lock.locked && !signedOut;
    final hasLockedChats = ref.watch(
      lockedConversationIdsProvider.select((ids) => ids.isNotEmpty),
    );
    final cover =
        !covered && _inactive && _isApple && (lock.enabled || hasLockedChats);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        ExcludeFocus(
          excluding: covered,
          child: Offstage(
            offstage: covered,
            child: TickerMode(enabled: !covered, child: widget.child),
          ),
        ),
        if (covered) const Positioned.fill(child: AppLockScreen()),
        if (cover) const Positioned.fill(child: PrivacyCover()),
      ],
    );
  }
}

/// The plain screen the app switcher shows instead of the last screen.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ColoredBox(
      key: const ValueKey('privacy-cover'),
      color: c.paper,
      child: Center(
        child: ExcludeSemantics(
          child: SettingsIconTile(
            icon: Icons.lock_outline_rounded,
            tone: SettingsTone.neutral,
            size: 64,
          ),
        ),
      ),
    );
  }
}

/// "WeCord is locked": the system's prompt (a button, and the prompt itself
/// when the app comes up) or the PIN keypad.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  static const screenKey = ValueKey('app-lock-screen');
  static const unlockKey = ValueKey('app-lock-unlock');

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  SystemAuthResult? _last;
  var _asking = false;

  @override
  void initState() {
    super.initState();
    // Coming up with the app (not while it sits in the background): ask at
    // once, so Face ID is waiting when the person looks at the phone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (!mounted) {
        return;
      }
      final prompt = ref.read(appLockProvider.notifier).takePromptOnShow();
      if (prompt &&
          (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
          ref.read(appLockProvider).method == LockMethod.system) {
        unawaited(_unlock());
      }
    });
  }

  Future<void> _unlock() async {
    if (_asking) {
      return;
    }
    setState(() => _asking = true);
    final result = await ref.read(appLockProvider.notifier).unlockWithSystem();
    if (mounted) {
      setState(() {
        _asking = false;
        _last = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final lock = ref.watch(appLockProvider);
    final system = lock.method == LockMethod.system;
    final unavailable = _last == SystemAuthResult.unavailable;
    return Scaffold(
      key: AppLockScreen.screenKey,
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(WeCordSpace.gutter + 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: system
                  ? _SystemLockBody(
                      asking: _asking,
                      unavailable: unavailable,
                      lockedOut: _last == SystemAuthResult.lockedOut,
                      onUnlock: () => unawaited(_unlock()),
                    )
                  : PinEntryView(
                      title: tr('WeCord is locked'),
                      subtitle: tr('Enter your PIN to open it.'),
                      waitUntil: lock.waitUntil,
                      footer: const ForgotPinButton(),
                      onSubmit: (pin) async {
                        final controller = ref.read(appLockProvider.notifier);
                        final result = controller.checkPin(pin);
                        if (result.ok) {
                          controller.unlock();
                          return null;
                        }
                        return pinProblemText(
                          result,
                          now: ref.read(lockClockProvider)(),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SystemLockBody extends ConsumerWidget {
  const _SystemLockBody({
    required this.asking,
    required this.unavailable,
    required this.lockedOut,
    required this.onUnlock,
  });

  final bool asking;
  final bool unavailable;
  final bool lockedOut;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SettingsIconTile(
            icon: Icons.lock_outline_rounded,
            tone: SettingsTone.accent,
            size: 64,
          ),
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            tr('WeCord is locked'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: c.ink,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          unavailable
              ? tr(
                  'This device can no longer check who you are. Sign out to '
                  'remove the lock, then sign in again.',
                )
              : lockedOut
              ? tr(
                  'Too many tries. Use your device passcode, or wait a '
                  'moment and try again.',
                )
              : tr('Unlock with Face ID, Touch ID or your device passcode.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: c.muted, height: 1.45),
        ),
        const SizedBox(height: 24),
        if (!unavailable)
          WeCordButton(
            key: AppLockScreen.unlockKey,
            label: tr('Unlock'),
            icon: Icons.lock_open_rounded,
            expand: true,
            size: WeCordButtonSize.large,
            loading: asking,
            onPressed: asking ? null : onUnlock,
          ),
        const SizedBox(height: 8),
        Center(child: ForgotPinButton(label: tr('Sign out'))),
      ],
    );
  }
}
