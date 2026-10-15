import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/profile/profile_extras_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle.dart';

/// Lets the current user pick an avatar just for [circleId], shown there
/// instead of their usual one, or go back to the usual one.
Future<void> showCircleAvatarSheet(
  BuildContext context, {
  required String circleId,
  required CircleMember member,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => CircleAvatarSheet(circleId: circleId, member: member),
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
    final theme = Theme.of(context);
    final profile = widget.member.profile;
    final circleAvatar = ref
        .watch(circleMemberAvatarsProvider(widget.circleId))
        .valueOrNull?[profile.id];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('Circle avatar'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              tr('Shown instead of your usual avatar in this circle only.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: FallbackAvatar(
                key: const ValueKey('circle-avatar-preview'),
                title: widget.member.displayName,
                avatarUrl: circleAvatar ?? profile.avatarUrl,
                radius: 36,
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('upload-circle-avatar'),
              onPressed: _busy ? null : _upload,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_camera_outlined),
              label: Text(tr('Upload image')),
            ),
            if (circleAvatar != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                key: const ValueKey('remove-circle-avatar'),
                onPressed: _busy ? null : _remove,
                icon: const Icon(Icons.restore),
                label: Text(tr('Use my usual avatar')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
