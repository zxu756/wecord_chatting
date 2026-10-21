import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/app_lock/lock_prompts.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens [child] (a chat page) only for a chat that is not locked, or one
/// the person has just opened with Face ID, Touch ID, the passcode or the
/// PIN. Until then it shows a plain page that says the chat is locked and
/// nothing about it: not its name, not its messages, and [child] is not even
/// built, so nothing is loaded.
///
/// A chat stays open while it is on screen and for a minute after it left,
/// and asks again after the app was out of sight (see [AppLockGate]).
class ChatLockGate extends ConsumerStatefulWidget {
  const ChatLockGate({
    required this.conversationId,
    required this.child,
    this.onBack,
    super.key,
  });

  final String conversationId;
  final Widget child;

  /// What the back arrow of the locked page does; goes back, or Home when
  /// there is nothing to go back to, by default.
  final VoidCallback? onBack;

  static const promptKey = ValueKey('chat-lock-prompt');
  static const unlockKey = ValueKey('chat-lock-unlock');

  @override
  ConsumerState<ChatLockGate> createState() => _ChatLockGateState();
}

class _ChatLockGateState extends ConsumerState<ChatLockGate> {
  late final ChatLockController _chatLock;

  /// The chat was opened before but its minute is over.
  var _expired = false;
  var _asking = false;
  SystemAuthResult? _last;

  @override
  void initState() {
    super.initState();
    _chatLock = ref.read(chatLockProvider.notifier);
    final id = widget.conversationId;
    final locked = ref.read(chatLockProvider).lockedIds.contains(id);
    if (locked) {
      final open = _chatLock.isOpen(id);
      _expired = !open;
      if (open) {
        _chatLock.markOpened(id);
      } else if (!ref.read(appLockProvider).hasPin) {
        // Face ID is waiting when the page comes up.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_unlockWithSystem());
          }
        });
      }
    }
  }

  @override
  void dispose() {
    try {
      _chatLock.markLeft(widget.conversationId);
    } on Object {
      // The app is closing.
    }
    super.dispose();
  }

  void _opened() {
    _chatLock.markOpened(widget.conversationId);
    if (mounted) {
      setState(() => _expired = false);
    }
  }

  Future<void> _unlockWithSystem() async {
    if (_asking) {
      return;
    }
    setState(() => _asking = true);
    final result = await ref
        .read(appLockProvider.notifier)
        .authenticateWithSystem(tr('Unlock this chat'));
    if (!mounted) {
      return;
    }
    setState(() {
      _asking = false;
      _last = result;
    });
    if (result == SystemAuthResult.success) {
      _opened();
    }
  }

  /// A device with no passcode (and the web) has no way to ask but a PIN of
  /// the app's own. The first time, the person makes one here.
  Future<void> _setPin() async {
    final made = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PinSetupPage(
          subtitle: tr('This PIN opens your locked chats on this device.'),
        ),
      ),
    );
    if (made == true && mounted) {
      _opened();
    }
  }

  void _back() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go(HomeScreen.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.conversationId;
    final locked = ref.watch(
      chatLockProvider.select((state) => state.lockedIds.contains(id)),
    );
    final opened = ref.watch(
      chatLockProvider.select((state) => state.unlockedIds.contains(id)),
    );
    if (!locked || (opened && !_expired)) {
      return widget.child;
    }
    final c = context.tokens.colors;
    final lock = ref.watch(appLockProvider);
    final pin = lock.hasPin;
    return Scaffold(
      key: ChatLockGate.promptKey,
      backgroundColor: c.paper,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(WeCordSpace.gutter + 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: pin
                      ? PinEntryView(
                          title: tr('This chat is locked'),
                          subtitle: tr('Enter your PIN to open it.'),
                          waitUntil: lock.waitUntil,
                          footer: const ForgotPinButton(),
                          onSubmit: (value) async {
                            final result = ref
                                .read(appLockProvider.notifier)
                                .checkPin(value);
                            if (result.ok) {
                              _opened();
                              return null;
                            }
                            return pinProblemText(
                              result,
                              now: ref.read(lockClockProvider)(),
                            );
                          },
                        )
                      : _SystemPrompt(
                          asking: _asking,
                          lockedOut: _last == SystemAuthResult.lockedOut,
                          needsPin: _last == SystemAuthResult.unavailable,
                          onUnlock: () => unawaited(_unlockWithSystem()),
                          onSetPin: () => unawaited(_setPin()),
                        ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: WeCordIconButton(
                key: const ValueKey('chat-lock-back'),
                icon: Icons.arrow_back_rounded,
                tooltip: tr('Back'),
                variant: WeCordButtonVariant.onPaper,
                onPressed: _back,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemPrompt extends StatelessWidget {
  const _SystemPrompt({
    required this.asking,
    required this.lockedOut,
    required this.needsPin,
    required this.onUnlock,
    required this.onSetPin,
  });

  final bool asking;
  final bool lockedOut;

  /// The device cannot ask; a PIN of the app's own is the way.
  final bool needsPin;
  final VoidCallback onUnlock;
  final VoidCallback onSetPin;

  @override
  Widget build(BuildContext context) {
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
            tr('This chat is locked'),
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
          needsPin
              ? tr('Set a PIN on this device to open your locked chats.')
              : lockedOut
              ? tr(
                  'Too many tries. Use your device passcode, or wait a '
                  'moment and try again.',
                )
              : tr('Unlock it with Face ID, Touch ID or your device passcode.'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, color: c.muted, height: 1.45),
        ),
        const SizedBox(height: 24),
        WeCordButton(
          key: ChatLockGate.unlockKey,
          label: needsPin ? tr('Set a PIN') : tr('Unlock'),
          icon: needsPin ? Icons.pin_outlined : Icons.lock_open_rounded,
          expand: true,
          size: WeCordButtonSize.large,
          loading: asking,
          onPressed: asking ? null : (needsPin ? onSetPin : onUnlock),
        ),
      ],
    );
  }
}
