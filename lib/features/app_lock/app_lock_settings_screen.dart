import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/app_lock/app_lock_controller.dart';
import 'package:wecord/features/app_lock/app_lock_models.dart';
import 'package:wecord/features/app_lock/chat_lock_actions.dart';
import 'package:wecord/features/app_lock/chat_lock_controller.dart';
import 'package:wecord/features/app_lock/lock_prompts.dart';
import 'package:wecord/features/app_lock/system_authenticator.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/privacy/option_picker.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings → Privacy & Safety → App lock.
void openAppLockSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => const AppLockSettingsScreen(),
    ),
  );
}

/// What the lock row in Privacy & Safety says: On or Off.
class AppLockSettingsRow extends ConsumerWidget {
  const AppLockSettingsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final on = ref.watch(appLockProvider.select((state) => state.enabled));
    final locked = ref.watch(
      lockedConversationIdsProvider.select((ids) => ids.length),
    );
    return SettingsRow(
      key: const ValueKey('app-lock-tile'),
      icon: Icons.lock_outline_rounded,
      tone: on ? SettingsTone.success : SettingsTone.neutral,
      title: tr('App lock and locked chats'),
      subtitle: tr('Ask for Face ID, Touch ID or a PIN, and lock single chats'),
      trailing: Text(
        on
            ? trIn('settings-state', 'On')
            : locked > 0
            ? tr('{count} locked', {'count': locked})
            : trIn('settings-state', 'Off'),
        style: TextStyle(
          fontSize: 13,
          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          color: on ? c.successText : c.muted,
        ),
      ),
      showChevron: true,
      onTap: () => openAppLockSettings(context),
    );
  }
}

/// App lock (when to ask, and how) and chat lock (which chats, hiding them,
/// the secret code), on one page.
class AppLockSettingsScreen extends ConsumerStatefulWidget {
  const AppLockSettingsScreen({super.key});

  static const screenKey = ValueKey('app-lock-settings-screen');

  @override
  ConsumerState<AppLockSettingsScreen> createState() =>
      _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends ConsumerState<AppLockSettingsScreen> {
  var _busy = false;

  void _say(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } on Object {
      if (mounted) {
        _say(
          tr('Could not change the lock. Check your connection and try again.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _setAppLock(bool on) => _run(() async {
    final controller = ref.read(appLockProvider.notifier);
    final lock = ref.read(appLockProvider);
    if (on) {
      final method = lock.hasPin
          ? LockMethod.pin
          : await controller.preferredMethod();
      if (!mounted) {
        return;
      }
      if (method == LockMethod.pin) {
        if (!lock.hasPin) {
          final made = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => PinSetupPage(
                subtitle: tr('This PIN opens WeCord after it was away.'),
              ),
            ),
          );
          if (made != true) {
            return;
          }
        }
      } else {
        // Face ID, Touch ID or the passcode must work before the app relies
        // on it.
        final result = await controller.authenticateWithSystem(
          tr('Turn on the app lock'),
        );
        if (result != SystemAuthResult.success) {
          if (result == SystemAuthResult.unavailable && mounted) {
            _say(
              tr(
                'Set a passcode on this device first, then turn the app lock on.',
              ),
            );
          }
          return;
        }
      }
      await controller.enable(method);
    } else {
      if (!await verifyOwner(
        context,
        ref,
        reason: tr('Turn off the app lock'),
      )) {
        return;
      }
      await controller.disable(
        keepPin: ref.read(chatLockProvider).lockedIds.isNotEmpty,
      );
      await tidyLockCredentials(ref);
    }
  });

  Future<void> _pickTimeout() async {
    final lock = ref.read(appLockProvider);
    final picked = await showOptionPicker<AppLockTimeout>(
      context,
      title: tr('Lock after'),
      selected: lock.timeout,
      note: tr(
        'How long WeCord may be out of sight before it asks again. On a '
        'computer, a window that is not in front counts as out of sight.',
      ),
      options: [
        for (final timeout in AppLockTimeout.values)
          PickerOption(value: timeout, title: timeout.label),
      ],
    );
    if (picked != null) {
      await ref.read(appLockProvider.notifier).setTimeout(picked);
    }
  }

  Future<void> _changePin() => _run(() async {
    final ok = await verifyOwner(
      context,
      ref,
      title: tr('Enter your current PIN'),
    );
    if (!ok || !mounted) {
      return;
    }
    final made = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PinSetupPage(),
      ),
    );
    if (made == true && mounted) {
      _say(tr('PIN changed.'));
    }
  });

  Future<void> _setHide(bool hide) => _run(() async {
    final chatLock = ref.read(chatLockProvider.notifier);
    if (hide && !ref.read(chatLockProvider).hasSecretCode) {
      final code = await showSecretCodeDialog(context);
      if (code == null) {
        return;
      }
      await chatLock.setSecretCode(code);
    }
    await chatLock.setHideLocked(hide);
  });

  Future<void> _editSecretCode() => _run(() async {
    final chatLock = ref.read(chatLockProvider.notifier);
    final has = ref.read(chatLockProvider).hasSecretCode;
    if (has) {
      final choice = await showOptionPicker<String>(
        context,
        title: tr('Secret code'),
        selected: '',
        options: [
          PickerOption(
            value: 'change',
            title: tr('Change the secret code'),
            icon: Icons.edit_outlined,
          ),
          PickerOption(
            value: 'remove',
            title: tr('Remove the secret code'),
            subtitle: tr('Locked chats then stay in the list.'),
            icon: Icons.delete_outline_rounded,
          ),
        ],
      );
      if (choice == null || !mounted) {
        return;
      }
      if (choice == 'remove') {
        await chatLock.setHideLocked(false);
        await chatLock.clearSecretCode();
        return;
      }
    }
    final code = await showSecretCodeDialog(context);
    if (code != null) {
      await chatLock.setSecretCode(code);
    }
  });

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final chats = ref.watch(chatLockProvider);
    final systemAvailable = ref.watch(systemAuthAvailableProvider).value;
    final conversations =
        ref.watch(conversationsProvider).value ?? const <ConversationSummary>[];
    final titles = {
      for (final conversation in conversations)
        conversation.id: conversation.title?.trim().isNotEmpty == true
            ? conversation.title!
            : tr('Conversation'),
    };
    final usesPin = lock.hasPin || (systemAvailable == false);
    final lockedList = chats.lockedIds.toList()
      ..sort((a, b) => (titles[a] ?? '').compareTo(titles[b] ?? ''));
    final c = context.tokens.colors;
    return SettingsPage(
      key: AppLockSettingsScreen.screenKey,
      title: tr('App lock'),
      children: [
        const SizedBox(height: 4),
        SettingsGroup(
          footer: usesPin
              ? (kIsWeb
                    ? tr(
                        'The PIN only covers the screen. It is not encryption, and it does not protect what this browser stores.',
                      )
                    : tr(
                        'This device has no passcode, so WeCord keeps a PIN of its own. It only covers the screen; set a device passcode for better protection.',
                      ))
              : tr(
                  'WeCord asks for Face ID, Touch ID or your device passcode when you come back after the time you choose.',
                ),
          children: [
            SettingsRow.toggle(
              key: const ValueKey('app-lock-toggle'),
              icon: Icons.lock_outline_rounded,
              tone: lock.enabled ? SettingsTone.success : SettingsTone.neutral,
              title: tr('App lock'),
              subtitle: usesPin
                  ? tr('Ask for a PIN when you open WeCord')
                  : tr('Ask for Face ID, Touch ID or the passcode'),
              value: lock.enabled,
              onChanged: _busy ? null : (on) => unawaited(_setAppLock(on)),
            ),
            if (lock.enabled)
              SettingsRow(
                key: const ValueKey('app-lock-timeout'),
                icon: Icons.timer_outlined,
                title: tr('Lock after'),
                value: lock.timeout.label,
                onTap: () => unawaited(_pickTimeout()),
              ),
            if (lock.enabled)
              SettingsRow(
                key: const ValueKey('app-lock-now'),
                icon: Icons.lock_clock_outlined,
                title: tr('Lock now'),
                showChevron: false,
                onTap: () {
                  ref.read(appLockProvider.notifier).lockNow();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            if (lock.hasPin)
              SettingsRow(
                key: const ValueKey('app-lock-change-pin'),
                icon: Icons.pin_outlined,
                title: tr('Change PIN'),
                onTap: _busy ? null : () => unawaited(_changePin()),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          header: tr('Locked chats'),
          footer: tr(
            'A locked chat asks to be unlocked, shows no message in the list, and its notifications show no sender and no text. WeCord AI questions and the daily digest leave it out.',
          ),
          children: [
            SettingsRow.toggle(
              key: const ValueKey('chat-lock-hide'),
              icon: Icons.visibility_off_outlined,
              title: tr('Hide locked chats'),
              subtitle: tr(
                'Leave them out of the lists until you type the secret code in search',
              ),
              value: chats.hideLocked,
              onChanged: _busy ? null : (hide) => unawaited(_setHide(hide)),
            ),
            SettingsRow(
              key: const ValueKey('chat-lock-secret'),
              icon: Icons.password_rounded,
              title: tr('Secret code'),
              value: chats.hasSecretCode ? tr('Set') : tr('Not set'),
              onTap: _busy ? null : () => unawaited(_editSecretCode()),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (lockedList.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              tr(
                'No locked chats yet. Open a chat, choose More, then Lock chat. You can also press and hold a chat in the list.',
              ),
              key: const ValueKey('chat-lock-none'),
              style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.45),
            ),
          )
        else
          SettingsGroup(
            children: [
              for (final id in lockedList)
                SettingsRow(
                  key: ValueKey('chat-lock-row-$id'),
                  icon: Icons.lock_rounded,
                  title: titles[id] ?? tr('Conversation'),
                  value: tr('Unlock'),
                  onTap: _busy
                      ? null
                      : () => unawaited(toggleChatLock(context, ref, id)),
                ),
            ],
          ),
      ],
    );
  }
}

/// Asks for a secret code twice (4 to 20 characters); null when cancelled.
/// Typing it in the search box shows the hidden chats.
Future<String?> showSecretCodeDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _SecretCodeDialog(),
  );
}

class _SecretCodeDialog extends StatefulWidget {
  const _SecretCodeDialog();

  @override
  State<_SecretCodeDialog> createState() => _SecretCodeDialogState();
}

class _SecretCodeDialogState extends State<_SecretCodeDialog> {
  final _code = TextEditingController();
  final _again = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _again.dispose();
    super.dispose();
  }

  void _save() {
    final code = _code.text.trim();
    if (code.length < secretCodeMinLength ||
        code.length > secretCodeMaxLength) {
      setState(() {
        _error = tr('Use {min} to {max} characters.', {
          'min': secretCodeMinLength,
          'max': secretCodeMaxLength,
        });
      });
      return;
    }
    if (code != _again.text.trim()) {
      setState(() => _error = tr('The two codes do not match.'));
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(tr('Secret code')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Type this code in the search box to show your hidden chats. It is kept on this device only.',
            ),
          ),
          const SizedBox(height: 16),
          WeCordTextField(
            fieldKey: const ValueKey('secret-code-field'),
            controller: _code,
            label: tr('Secret code'),
            autofocus: true,
            obscureText: true,
            inputFormatters: [
              LengthLimitingTextInputFormatter(secretCodeMaxLength),
            ],
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          WeCordTextField(
            fieldKey: const ValueKey('secret-code-again'),
            controller: _again,
            label: tr('Type it again'),
            obscureText: true,
            inputFormatters: [
              LengthLimitingTextInputFormatter(secretCodeMaxLength),
            ],
            errorText: _error,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          key: const ValueKey('secret-code-save'),
          onPressed: _save,
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}
