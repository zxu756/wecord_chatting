import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/circles/circle_tag_widgets.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/profile/profile_banner.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/features/settings/settings_providers.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings → Edit profile.
Future<void> openProfileEditor(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const ProfileEditScreen()),
  );
}

/// The phone page for editing the current user's profile.
class ProfileEditScreen extends ConsumerWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider);
    return SettingsPage(
      key: const ValueKey('profile-edit-screen'),
      title: tr('Edit profile'),
      children: [
        switch (profile) {
          AsyncData(:final value) => ProfileEditor(profile: value),
          AsyncError(:final error) => SettingsErrorText(error),
          _ => const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          ),
        },
      ],
    );
  }
}

/// The current user's banner, avatar, display name, pronouns, bio and
/// circle tag, with Save.
class ProfileEditor extends ConsumerStatefulWidget {
  const ProfileEditor({required this.profile, super.key});

  final Profile profile;

  @override
  ConsumerState<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<ProfileEditor> {
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _pronounsController = TextEditingController();
  String? _avatarUrl;
  String? _bannerUrl;
  String? _errorText;
  var _saving = false;
  var _uploadingAvatar = false;
  var _uploadingBanner = false;

  @override
  void initState() {
    super.initState();
    _load(widget.profile);
  }

  @override
  void didUpdateWidget(ProfileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      _load(widget.profile);
    }
  }

  void _load(Profile profile) {
    _displayNameController.text = profile.displayName;
    _bioController.text = profile.bio;
    _pronounsController.text = profile.pronouns ?? '';
    _avatarUrl = profile.avatarUrl;
    _bannerUrl = profile.bannerUrl;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _pronounsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final profile = widget.profile;
    final inWindow = SettingsWindowScope.maybeOf(context) != null;
    final presence = ref.watch(ownPresenceProvider);
    final name = _displayNameController.text.trim().isEmpty
        ? profile.username
        : _displayNameController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Banner, avatar and the picture buttons.
        Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileBannerHeader(
                bannerUrl: _bannerUrl,
                colorSeed: name,
                bannerHeight: inWindow ? 140 : 118,
                avatarSize: inWindow ? 88 : 80,
                overlap: 46,
                avatar: ProfileAvatar(
                  key: const ValueKey('profile-editor-avatar'),
                  name: name,
                  avatarUrl: _avatarUrl,
                  size: inWindow ? 88 : 80,
                  presence: presenceColor(context, presence),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: c.ink,
                      ),
                    ),
                    Text(
                      '@${profile.username}',
                      style: TextStyle(fontSize: 14, color: c.muted),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        WeCordButton(
                          key: const ValueKey('change-avatar'),
                          label: tr('Change avatar'),
                          icon: Icons.photo_camera_outlined,
                          variant: WeCordButtonVariant.secondary,
                          size: WeCordButtonSize.small,
                          loading: _uploadingAvatar,
                          onPressed: _changeAvatar,
                        ),
                        WeCordButton(
                          key: const ValueKey('change-banner'),
                          label: tr('Change banner'),
                          icon: Icons.panorama_outlined,
                          variant: WeCordButtonVariant.secondary,
                          size: WeCordButtonSize.small,
                          loading: _uploadingBanner,
                          onPressed: _changeBanner,
                        ),
                        if (_bannerUrl != null)
                          WeCordButton(
                            key: const ValueKey('remove-banner'),
                            label: tr('Remove banner'),
                            icon: Icons.hide_image_outlined,
                            variant: WeCordButtonVariant.ghost,
                            size: WeCordButtonSize.small,
                            onPressed: _uploadingBanner
                                ? null
                                : () => setState(() => _bannerUrl = null),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SettingsSectionHeader(tr('About you')),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WeCordTextField(
                fieldKey: const ValueKey('display-name'),
                controller: _displayNameController,
                label: tr('Display name'),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              WeCordTextField(
                fieldKey: const ValueKey('pronouns'),
                controller: _pronounsController,
                label: tr('Pronouns'),
                hint: tr('Add your pronouns'),
                maxLength: Profile.maxPronounsLength,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 4),
              WeCordTextField(
                fieldKey: const ValueKey('bio'),
                controller: _bioController,
                label: tr('Bio'),
                hint: tr('A line or two about you'),
                minLines: 3,
                maxLines: 5,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const SettingsGroup(children: [CircleTagSettingTile()]),
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
            child: Text(
              _errorText!,
              style: TextStyle(fontSize: 13.5, color: c.dangerText),
            ),
          ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: WeCordButton(
            key: const ValueKey('profile-save'),
            label: tr('Save'),
            size: inWindow ? WeCordButtonSize.medium : WeCordButtonSize.large,
            expand: !inWindow,
            loading: _saving,
            onPressed: _saveProfile,
          ),
        ),
      ],
    );
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
      final saved = ref.read(currentProfileProvider).value;
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
}

/// An error shown in place of a settings page's content.
class SettingsErrorText extends StatelessWidget {
  const SettingsErrorText(this.error, {super.key});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
      child: Text(
        error.toString(),
        style: TextStyle(color: context.tokens.colors.dangerText),
      ),
    );
  }
}
