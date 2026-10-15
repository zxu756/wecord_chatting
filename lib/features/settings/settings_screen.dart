import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/conversation_navigation.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/presence/presence_status_sheet.dart';
import 'package:wecord/features/settings/two_factor_settings_screen.dart';
import 'package:wecord/features/settings/custom_status_sheet.dart';
import 'package:wecord/features/profile/profile_banner.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/features/push/push_controller.dart';
import 'package:wecord/features/push/push_settings_tile.dart';
import 'package:wecord/features/settings/account_deletion.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/voice/voice_settings_screen.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/theme/theme_mode_controller.dart';

final currentProfileProvider = FutureProvider.autoDispose<Profile>((ref) {
  return ref.watch(settingsRepositoryProvider).currentProfile();
});

final blockedUsersProvider = FutureProvider.autoDispose<List<Profile>>((ref) {
  return ref.watch(settingsRepositoryProvider).listBlockedUsers();
});

final currentNotificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferences>((ref) {
      return ref.watch(notificationPreferencesRepositoryProvider).load();
    });

final currentNotificationPermissionStatusProvider =
    FutureProvider.autoDispose<NotificationPermissionStatus>((ref) {
      return ref.watch(localNotificationServiceProvider).permissionStatus();
    });

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static const path = '/me';

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _pronounsController = TextEditingController();
  String? _loadedProfileId;
  String? _avatarUrl;
  String? _bannerUrl;
  String? _errorText;
  var _saving = false;
  var _uploadingAvatar = false;
  var _uploadingBanner = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _pronounsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider);
    final notificationPreferences =
        ref.watch(currentNotificationPreferencesProvider).valueOrNull ??
        NotificationPreferences.defaults;
    final notificationPermissionStatus =
        ref.watch(currentNotificationPermissionStatusProvider).valueOrNull ??
        NotificationPermissionStatus.notRequested;

    return Scaffold(
      appBar: AppBar(
        leading: phoneHomeBackButton(context),
        title: Text(tr('You')),
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: _ErrorText(error)),
        data: (profile) {
          _syncProfile(profile);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ProfileBannerHeader(
                bannerUrl: _bannerUrl,
                avatar: _ProfileAvatar(
                  displayName: _displayNameController.text,
                  avatarUrl: _avatarUrl,
                  radius: 42,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _uploadingAvatar ? null : _changeAvatar,
                    icon: _uploadingAvatar
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_camera_outlined),
                    label: Text(tr('Change avatar')),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('change-banner'),
                    onPressed: _uploadingBanner ? null : _changeBanner,
                    icon: _uploadingBanner
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.panorama_outlined),
                    label: Text(tr('Change banner')),
                  ),
                  if (_bannerUrl != null)
                    TextButton.icon(
                      key: const ValueKey('remove-banner'),
                      onPressed: _uploadingBanner
                          ? null
                          : () => setState(() => _bannerUrl = null),
                      icon: const Icon(Icons.hide_image_outlined),
                      label: Text(tr('Remove banner')),
                    ),
                  _PresenceButton(
                    status: ref.watch(ownPresenceProvider),
                    onPressed: () => showPresenceStatusSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _CustomStatusTile(
                status: activeCustomStatus(profile.customStatus),
                onTap: () => _editCustomStatus(profile),
              ),
              const SizedBox(height: 8),
              Text('@${profile.username}'),
              const SizedBox(height: 12),
              TextField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: tr('Display name'),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('pronouns'),
                controller: _pronounsController,
                maxLength: Profile.maxPronounsLength,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: tr('Pronouns'),
                  hintText: tr('Add your pronouns'),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _bioController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: tr('Bio'),
                ),
                minLines: 3,
                maxLines: 5,
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _saveProfile,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('Save')),
              ),
              const Divider(height: 32),
              Text(
                tr('Appearance'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                key: const ValueKey('theme-mode'),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: const Icon(Icons.brightness_auto_outlined),
                    label: Text(tr('System')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: const Icon(Icons.light_mode_outlined),
                    label: Text(tr('Light')),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: const Icon(Icons.dark_mode_outlined),
                    label: Text(tr('Dark')),
                  ),
                ],
                selected: {ref.watch(themeModeProvider)},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    ref.read(themeModeProvider.notifier).set(selection.single),
              ),
              const SizedBox(height: 16),
              Text(
                tr('Language'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SegmentedButton<AppLanguage>(
                key: const ValueKey('app-language'),
                segments: [
                  ButtonSegment(
                    value: AppLanguage.system,
                    label: Text(tr('System')),
                  ),
                  const ButtonSegment(
                    value: AppLanguage.english,
                    label: Text('English'),
                  ),
                  const ButtonSegment(
                    value: AppLanguage.chinese,
                    label: Text('中文'),
                  ),
                ],
                selected: {ref.watch(appLanguageProvider)},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => ref
                    .read(appLanguageProvider.notifier)
                    .set(selection.single),
              ),
              const Divider(height: 32),
              ListTile(
                key: const ValueKey('voice-settings-tile'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.headset_mic_outlined),
                title: Text(tr('Voice')),
                subtitle: Text(
                  tr('Push to talk, noise suppression and echo cancellation'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openVoiceSettings(context),
              ),
              const Divider(height: 32),
              Text(
                tr('Account'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ListTile(
                key: const ValueKey('two-factor-settings-tile'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phonelink_lock_outlined),
                title: Text(tr('Two-step verification')),
                subtitle: Text(
                  tr(
                    'Ask for a code from an authenticator app when signing in',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => openTwoFactorSettings(context),
              ),
              const Divider(height: 32),
              Text(
                tr('Privacy & Safety'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined),
                title: Text(tr('Blocked users')),
                subtitle: Text(tr('Manage people you have blocked')),
                onTap: () => showBlockedUsersSheet(context, ref),
              ),
              SwitchListTile(
                key: const ValueKey('show-online-status'),
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.visibility_outlined),
                title: Text(tr('Show when you are online')),
                subtitle: Text(
                  tr('When off, everyone else sees you as offline.'),
                ),
                value:
                    ref
                        .watch(presenceSettingsProvider)
                        .valueOrNull
                        ?.showOnlineStatus ??
                    true,
                onChanged: _setShowOnlineStatus,
              ),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Notifications')),
                value: notificationPreferences.enabled,
                onChanged: (enabled) {
                  _saveNotificationPreferences(
                    notificationPreferences.copyWith(enabled: enabled),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Message previews')),
                value: notificationPreferences.showPreviews,
                onChanged: notificationPreferences.enabled
                    ? (showPreviews) {
                        _saveNotificationPreferences(
                          notificationPreferences.copyWith(
                            showPreviews: showPreviews,
                          ),
                        );
                      }
                    : null,
              ),
              const PushSettingsTile(),
              Text(
                _permissionStatusLabel(notificationPermissionStatus),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _requestNotificationPermission,
                    child: Text(tr('Request permission')),
                  ),
                  OutlinedButton(
                    onPressed: _sendTestNotification,
                    child: Text(tr('Send test notification')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saving ? null : _signOut,
                child: Text(tr('Sign out')),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey('delete-account'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: _saving
                    ? null
                    : () => confirmAndDeleteAccount(
                        context,
                        ref,
                        username: profile.username,
                      ),
                icon: const Icon(Icons.delete_forever_outlined),
                label: Text(tr('Delete account')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _syncProfile(Profile profile) {
    if (_loadedProfileId == profile.id) {
      return;
    }
    _loadedProfileId = profile.id;
    _displayNameController.text = profile.displayName;
    _bioController.text = profile.bio;
    _pronounsController.text = profile.pronouns ?? '';
    _avatarUrl = profile.avatarUrl;
    _bannerUrl = profile.bannerUrl;
  }

  Future<void> _saveProfile() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateProfile(
            displayName: _displayNameController.text.trim(),
            bio: _bioController.text.trim(),
            avatarUrl: _avatarUrl,
          );
      // Pronouns and banner are saved separately, and only when changed.
      final saved = ref.read(currentProfileProvider).valueOrNull;
      final pronouns = _pronounsController.text.trim();
      if (saved == null ||
          pronouns != (saved.pronouns ?? '') ||
          _bannerUrl != saved.bannerUrl) {
        await ref
            .read(profileExtrasRepositoryProvider)
            .updateProfileExtras(pronouns: pronouns, bannerUrl: _bannerUrl);
      }
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = tr('Could not save profile. Try again.');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _changeAvatar() async {
    setState(() {
      _uploadingAvatar = true;
      _errorText = null;
    });

    try {
      final image = await ref.read(imagePickerServiceProvider).pickImage();
      if (image == null) {
        return;
      }
      final avatarPath = await ref
          .read(settingsRepositoryProvider)
          .uploadAvatar(
            fileName: image.fileName,
            mimeType: image.mimeType,
            bytes: image.bytes,
          );
      if (mounted) {
        setState(() {
          _avatarUrl = avatarPath;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = tr('Could not upload avatar. Try again.');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _changeBanner() async {
    setState(() {
      _uploadingBanner = true;
      _errorText = null;
    });

    try {
      final image = await ref.read(imagePickerServiceProvider).pickImage();
      if (image == null) {
        return;
      }
      final bannerPath = await ref
          .read(profileExtrasRepositoryProvider)
          .uploadBanner(
            fileName: image.fileName,
            mimeType: image.mimeType,
            bytes: image.bytes,
          );
      if (mounted) {
        setState(() {
          _bannerUrl = bannerPath;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = tr('Could not upload banner. Try again.');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingBanner = false;
        });
      }
    }
  }

  Future<void> _editCustomStatus(Profile profile) async {
    final saved = await showCustomStatusSheet(
      context,
      current: activeCustomStatus(profile.customStatus),
    );
    if (saved == true) {
      ref.invalidate(currentProfileProvider);
    }
  }

  Future<void> _setShowOnlineStatus(bool show) async {
    try {
      await ref
          .read(presenceSettingsProvider.notifier)
          .setShowOnlineStatus(show);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = tr('Could not save privacy settings. Try again.');
        });
      }
    }
  }

  Future<void> _signOut() async {
    await stopPushForSignOut(ref);
    await ref.read(authRepositoryProvider).signOut();
  }

  Future<void> _saveNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    await ref.read(notificationPreferencesRepositoryProvider).save(preferences);
    ref.invalidate(currentNotificationPreferencesProvider);
  }

  Future<void> _requestNotificationPermission() async {
    await ref.read(localNotificationServiceProvider).requestPermission();
    ref.invalidate(currentNotificationPermissionStatusProvider);
  }

  Future<void> _sendTestNotification() async {
    final notificationService = ref.read(localNotificationServiceProvider);
    final status = await notificationService.requestPermission();
    ref.invalidate(currentNotificationPermissionStatusProvider);
    if (status != NotificationPermissionStatus.granted) {
      if (mounted) {
        setState(() {
          _errorText = tr('Notifications are not allowed on this device.');
        });
      }
      return;
    }

    try {
      await notificationService.showMessageNotification(
        conversationId: 'settings-test',
        title: 'WeCord',
        body: tr('Notifications are working.'),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = tr('Could not send test notification. Try again.');
        });
      }
    }
  }
}

/// The current user's Online / Idle / Do Not Disturb / Invisible status;
/// opens the status picker.
class _PresenceButton extends StatelessWidget {
  const _PresenceButton({required this.status, required this.onPressed});

  final PresenceStatus status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const ValueKey('presence-status-tile'),
      onPressed: onPressed,
      icon: PresenceIndicator(
        status: status,
        borderColor: Theme.of(context).colorScheme.surface,
        size: 14,
      ),
      label: Text(status.label),
    );
  }
}

class _CustomStatusTile extends StatelessWidget {
  const _CustomStatusTile({required this.status, required this.onTap});

  final CustomStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final expiresAt = status?.expiresAt;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: status?.emoji == null
            ? const Icon(Icons.add_reaction_outlined)
            : Text(status!.emoji!, style: const TextStyle(fontSize: 22)),
        title: Text(
          status == null
              ? tr('Set status')
              : (status.text ?? status.emoji ?? tr('Status')),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: status == null
            ? null
            : Text(
                expiresAt == null
                    ? tr("Doesn't clear")
                    : _formatExpiry(expiresAt),
              ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: onTap,
      ),
    );
  }
}

String _formatExpiry(DateTime expiresAt) {
  final local = expiresAt.toLocal();
  final now = DateTime.now();
  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) {
    return tr('Clears at {time}', {'time': time});
  }
  return tr('Clears on {month}/{day} at {time}', {
    'month': local.month,
    'day': local.day,
    'time': time,
  });
}

Future<void> showBlockedUsersSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _BlockedUsersSheet(),
  );
}

class _BlockedUsersSheet extends ConsumerStatefulWidget {
  const _BlockedUsersSheet();

  @override
  ConsumerState<_BlockedUsersSheet> createState() => _BlockedUsersSheetState();
}

class _BlockedUsersSheetState extends ConsumerState<_BlockedUsersSheet> {
  String? _unblockingUserId;

  @override
  Widget build(BuildContext context) {
    final blockedUsers = ref.watch(blockedUsersProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Blocked users'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Flexible(
              child: blockedUsers.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, stackTrace) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: _ErrorText(error),
                ),
                data: (users) {
                  if (users.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(tr('You have not blocked anyone.')),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: users.length,
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final user = users[index];
                      final isUnblocking = _unblockingUserId == user.id;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(user.displayLabel),
                        subtitle: Text('@${user.username}'),
                        trailing: TextButton(
                          onPressed: isUnblocking
                              ? null
                              : () => _unblockUser(user.id),
                          child: isUnblocking
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(tr('Unblock')),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unblockUser(String userId) async {
    setState(() {
      _unblockingUserId = userId;
    });
    try {
      await ref.read(settingsRepositoryProvider).unblockUser(userId);
      ref.invalidate(blockedUsersProvider);
    } finally {
      if (mounted) {
        setState(() {
          _unblockingUserId = null;
        });
      }
    }
  }
}

class _ProfileAvatar extends ConsumerWidget {
  const _ProfileAvatar({
    required this.displayName,
    required this.avatarUrl,
    this.radius = 20,
  });

  final String displayName;
  final String? avatarUrl;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayUrl = ref.watch(avatarDisplayUrlProvider(avatarUrl));
    final image = displayUrl.valueOrNull == null
        ? null
        : NetworkImage(displayUrl.valueOrNull!);
    return CircleAvatar(
      radius: radius,
      backgroundImage: image,
      onBackgroundImageError: image == null
          ? null
          : (_, _) => refreshAvatarDisplayUrl(ref, avatarUrl),
      child: image == null ? Text(_initials(displayName)) : null,
    );
  }
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return '?';
  }
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts.last.characters.first : '';
  return '$first$second'.toUpperCase();
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.error);

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Text(
      error.toString(),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}

String _permissionStatusLabel(NotificationPermissionStatus status) {
  return switch (status) {
    NotificationPermissionStatus.notRequested => tr('Permission not requested'),
    NotificationPermissionStatus.granted => tr('Permission granted'),
    NotificationPermissionStatus.denied => tr('Permission denied'),
    NotificationPermissionStatus.unavailable => tr('Notifications unavailable'),
  };
}
