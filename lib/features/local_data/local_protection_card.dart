import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/local_data/local_cipher.dart';
import 'package:wecord/features/local_data/local_cipher_provider.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How the chats saved on this device are protected (G8), as Settings →
/// Storage tells it. It says what is encrypted, where the key is, how far
/// that protection goes on this platform (honestly: far less in a browser)
/// and what is not covered.
class LocalProtectionCard extends ConsumerWidget {
  const LocalProtectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final protection = ref.watch(localCipherProvider.select((c) => c.protection));
    return LocalProtectionGroup(protection: protection);
  }
}

/// [LocalProtectionCard] for a given level of protection.
class LocalProtectionGroup extends StatelessWidget {
  const LocalProtectionGroup({required this.protection, super.key});

  final LocalProtection protection;

  @override
  Widget build(BuildContext context) {
    final (icon, tone, title, body) = switch (protection) {
      LocalProtection.keychain => (
        Icons.lock_outline_rounded,
        SettingsTone.success,
        tr('Saved chats are encrypted'),
        tr(
          'Cached messages, recognized text, drafts and the offline search index are encrypted. The key is kept in the system Keychain, not in WeCord\'s files, and is not copied to backups or other devices. Signing out deletes the key and the saved chats.',
        ),
      ),
      LocalProtection.browserKey => (
        Icons.lock_open_rounded,
        SettingsTone.warning,
        tr('Encrypted in this browser, with limits'),
        tr(
          'Saved messages, recognized text, drafts and the offline search index are encrypted with a key your browser makes and will not hand out. That keeps the saved data from being read as plain text, but it is weaker than on the phone or Mac: the key sits in the same browser profile, and pages or extensions running in this browser can still use it. On a shared computer, sign out when you are done; that deletes the key and the saved chats.',
        ),
      ),
      LocalProtection.session => (
        Icons.lock_clock_outlined,
        SettingsTone.neutral,
        tr('Encrypted for this session only'),
        tr(
          'The key is not kept anywhere, so saved chats cannot be read after the app closes.',
        ),
      ),
      LocalProtection.unavailable => (
        Icons.no_encryption_outlined,
        SettingsTone.danger,
        tr('Saved chats are switched off'),
        tr(
          'The key that protects saved chats could not be opened on this device, so WeCord keeps no copy of your chats here and nothing is stored in plain text. You can still use WeCord while you are online.',
        ),
      ),
    };
    return SettingsGroup(
      header: tr('Protection on this device'),
      footer: tr(
        'Downloaded pictures, videos and files are kept as ordinary files and are not encrypted by WeCord. Clear them above, or rely on your device\'s own protection (screen lock, FileVault).',
      ),
      children: [
        SettingsRow(
          key: const ValueKey('storage-protection'),
          icon: icon,
          tone: tone,
          title: title,
          subtitle: body,
        ),
        SettingsRow(
          key: const ValueKey('storage-offline-search'),
          icon: Icons.manage_search_rounded,
          title: tr('Search without a connection'),
          subtitle: tr(
            'Without a connection, search looks through the newest messages saved on this device. The search index is encrypted the same way, and is emptied as messages are deleted or expire, or when you clear cached messages.',
          ),
        ),
      ],
    );
  }
}
