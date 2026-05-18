import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/profile.dart';

final currentProfileProvider = FutureProvider.autoDispose<Profile>((ref) {
  return ref.watch(settingsRepositoryProvider).currentProfile();
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
  String? _loadedProfileId;
  String? _avatarUrl;
  String? _errorText;
  var _saving = false;
  var _uploadingAvatar = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
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
      appBar: AppBar(title: const Text('Me')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: _ErrorText(error)),
        data: (profile) {
          _syncProfile(profile);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: _ProfileAvatar(
                  displayName: _displayNameController.text,
                  avatarUrl: _avatarUrl,
                  radius: 42,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton.icon(
                  onPressed: _uploadingAvatar ? null : _changeAvatar,
                  icon: _uploadingAvatar
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera_outlined),
                  label: const Text('Change avatar'),
                ),
              ),
              const SizedBox(height: 24),
              Text('@${profile.username}'),
              const SizedBox(height: 12),
              TextField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Display name',
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bioController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Bio',
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
                    : const Text('Save'),
              ),
              const SizedBox(height: 8),
              const Divider(height: 32),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Notifications'),
                value: notificationPreferences.enabled,
                onChanged: (enabled) {
                  _saveNotificationPreferences(
                    notificationPreferences.copyWith(enabled: enabled),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Message previews'),
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
              Text(
                _permissionStatusLabel(notificationPermissionStatus),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: _requestNotificationPermission,
                  child: const Text('Request permission'),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saving ? null : _signOut,
                child: const Text('Sign out'),
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
    _avatarUrl = profile.avatarUrl;
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
      ref.invalidate(currentProfileProvider);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorText = 'Could not save profile. Try again.';
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
          _errorText = 'Could not upload avatar. Try again.';
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

  Future<void> _signOut() {
    return ref.read(authRepositoryProvider).signOut();
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
      onBackgroundImageError: image == null ? null : (_, _) {},
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
    NotificationPermissionStatus.notRequested => 'Permission not requested',
    NotificationPermissionStatus.granted => 'Permission granted',
    NotificationPermissionStatus.denied => 'Permission denied',
    NotificationPermissionStatus.unavailable => 'Notifications unavailable',
  };
}
