import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Lets the current user pick an avatar just for [circleId], shown there
/// instead of their usual one, or go back to the usual one.
Future<void> showCircleAvatarSheet(
  BuildContext context, {
  required String circleId,
  required CircleMember member,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Circle avatar'),
    builder: (_, _) => CircleAvatarSheet(circleId: circleId, member: member),
  );
}

class CircleAvatarSheet extends ConsumerStatefulWidget {
  const CircleAvatarSheet({
    required this.circleId,
    required this.member,
    super.key,
  });

  final String circleId;

  /// The current user's membership.
  final CircleMember member;

  @override
  ConsumerState<CircleAvatarSheet> createState() => _CircleAvatarSheetState();
}

class _CircleAvatarSheetState extends ConsumerState<CircleAvatarSheet> {
  var _busy = false;
  String? _errorText;

  Future<void> _run(Future<void> Function() action, String error) async {
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errorText = error;
        });
      }
    }
  }

  Future<void> _upload() {
    return _run(() async {
      final image = await ref.read(imagePickerServiceProvider).pickImage();
      if (image == null) {
        if (mounted) {
          setState(() => _busy = false);
        }
        return;
      }
      final repository = ref.read(profileExtrasRepositoryProvider);
      final path = await repository.uploadCircleAvatar(
        circleId: widget.circleId,
        fileName: image.fileName,
        mimeType: image.mimeType,
        bytes: image.bytes,
      );
      await repository.setCircleAvatar(
        circleId: widget.circleId,
        avatarUrl: path,
      );
      _done();
    }, tr('Could not upload avatar. Try again.'));
  }

  Future<void> _remove() {
    return _run(() async {
      await ref
          .read(profileExtrasRepositoryProvider)
          .setCircleAvatar(circleId: widget.circleId, avatarUrl: null);
      _done();
    }, tr('Could not remove the circle avatar. Try again.'));
  }

  void _done() {
    ref.invalidate(circleMemberAvatarsProvider(widget.circleId));
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final profile = widget.member.profile;
    final circleAvatar = ref
        .watch(circleMemberAvatarsProvider(widget.circleId))
        .value?[profile.id];
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Shown instead of your usual avatar in this circle only.'),
              style: TextStyle(fontSize: 14, height: 1.45, color: c.muted),
            ),
            const SizedBox(height: 18),
            Center(
              child: ProfileAvatar(
                key: const ValueKey('circle-avatar-preview'),
                name: widget.member.displayName,
                avatarUrl: circleAvatar ?? profile.avatarUrl,
                size: 84,
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ],
            const SizedBox(height: 20),
            WeCordButton(
              key: const ValueKey('upload-circle-avatar'),
              label: tr('Upload image'),
              icon: Icons.photo_camera_outlined,
              size: WeCordButtonSize.large,
              expand: true,
              loading: _busy,
              onPressed: _upload,
            ),
            if (circleAvatar != null) ...[
              const SizedBox(height: 8),
              WeCordButton(
                key: const ValueKey('remove-circle-avatar'),
                label: tr('Use my usual avatar'),
                icon: Icons.restore_rounded,
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: _busy ? null : _remove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
