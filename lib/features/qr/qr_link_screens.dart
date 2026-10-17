import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/qr/group_qr_sheet.dart';
import 'package:wecord/features/qr/qr_links.dart';
import 'package:wecord/features/qr/qr_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What opening a QR link is doing.
enum _Step { opening, failed, gone }

/// `/u/<code>`: a person's QR code opened as a link (from the browser, or
/// after scanning). It looks the code up and replaces itself with that
/// person's profile, where Add friend and Message are.
class UserQrLinkScreen extends ConsumerStatefulWidget {
  const UserQrLinkScreen({required this.code, super.key});

  static const path = userQrRoutePrefix;

  final String code;

  @override
  ConsumerState<UserQrLinkScreen> createState() => _UserQrLinkScreenState();
}

class _UserQrLinkScreenState extends ConsumerState<UserQrLinkScreen> {
  var _step = _Step.opening;

  @override
  void initState() {
    super.initState();
    unawaited(Future.microtask(_open));
  }

  Future<void> _open() async {
    if (!mounted) {
      return;
    }
    setState(() => _step = _Step.opening);
    final QrProfile? profile;
    try {
      profile = await ref.read(qrRepositoryProvider).resolveUser(widget.code);
    } on Object {
      if (mounted) {
        setState(() => _step = _Step.failed);
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (profile == null) {
      setState(() => _step = _Step.gone);
      return;
    }
    context.pushReplacement('${UserProfileScreen.path}/${profile.id}');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final Widget body = switch (_step) {
      _Step.opening => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Semantics(
              liveRegion: true,
              child: Text(
                tr('Opening the QR code…'),
                key: const ValueKey('qr-link-status'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.ink,
                ),
              ),
            ),
          ],
        ),
      ),
      _Step.failed => CircleEmptyState(
        icon: Icons.error_outline_rounded,
        title: tr('Could not open the QR code'),
        message: tr('Check your connection and try again.'),
        action: WeCordButton(
          key: const ValueKey('qr-link-retry'),
          variant: WeCordButtonVariant.onPaper,
          onPressed: _open,
          label: tr('Try again'),
        ),
      ),
      _Step.gone => CircleEmptyState(
        icon: Icons.qr_code_2_rounded,
        title: tr("This QR code doesn't work"),
        message: tr(
          'It may have been reset, or the person is not available. Ask them '
          'for a new one.',
        ),
        action: WeCordButton(
          key: const ValueKey('qr-link-home'),
          variant: WeCordButtonVariant.onPaper,
          onPressed: () => context.go(HomeScreen.path),
          label: tr('Back to home'),
        ),
      ),
    };
    return CirclePageScaffold(
      title: tr('QR code'),
      constrainBody: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: body,
        ),
      ),
    );
  }
}

/// `/g/<code>`: a group chat's QR code opened as a link: shows the group and
/// lets the person join it.
class GroupQrJoinScreen extends ConsumerStatefulWidget {
  const GroupQrJoinScreen({required this.code, super.key});

  static const path = groupQrRoutePrefix;

  final String code;

  @override
  ConsumerState<GroupQrJoinScreen> createState() => _GroupQrJoinScreenState();
}

class _GroupQrJoinScreenState extends ConsumerState<GroupQrJoinScreen> {
  GroupQrPreview? _preview;
  var _loading = true;
  var _failed = false;
  var _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(Future.microtask(_load));
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final preview = await ref
          .read(qrRepositoryProvider)
          .previewGroup(widget.code);
      if (mounted) {
        setState(() => _preview = preview);
      }
    } on Object {
      if (mounted) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openChat(GroupQrPreview preview, String conversationId) {
    ref.invalidate(conversationsProvider);
    context.go(
      '${ChatsScreen.path}/$conversationId',
      extra: ChatThreadRouteExtra(
        title: preview.title ?? tr('Group'),
        type: ConversationType.group,
        avatarUrl: preview.avatarUrl,
      ),
    );
  }

  Future<void> _join(GroupQrPreview preview) async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(qrRepositoryProvider)
          .joinGroup(widget.code);
      if (!mounted) {
        return;
      }
      if (result.inGroup && result.conversationId != null) {
        _openChat(preview, result.conversationId!);
        return;
      }
      // It ran out (or was refreshed) a moment ago.
      await _load();
    } on Object {
      if (mounted) {
        setState(() => _error = tr("Couldn't join the group. Try again."));
      }
    } finally {
      if (mounted) {
        setState(() => _joining = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final preview = _preview;
    final Widget body;
    if (_loading && preview == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_failed || preview == null) {
      body = CircleEmptyState(
        icon: Icons.error_outline_rounded,
        title: tr('Could not open the QR code'),
        message: tr('Check your connection and try again.'),
        action: WeCordButton(
          key: const ValueKey('qr-link-retry'),
          variant: WeCordButtonVariant.onPaper,
          onPressed: _load,
          label: tr('Try again'),
        ),
      );
    } else if (!preview.canShow) {
      final expired = preview.state == GroupQrState.expired;
      body = CircleEmptyState(
        icon: Icons.link_off_rounded,
        title: expired
            ? tr('This group QR code has expired')
            : tr("This group QR code doesn't work"),
        message: expired
            ? tr('Ask a group admin for a new one.')
            : tr('Check that the whole code was scanned, then try again.'),
        action: WeCordButton(
          key: const ValueKey('qr-link-home'),
          variant: WeCordButtonVariant.onPaper,
          onPressed: () => context.go(HomeScreen.path),
          label: tr('Back to home'),
        ),
      );
    } else {
      final title = preview.title?.trim().isNotEmpty == true
          ? preview.title!.trim()
          : tr('Group');
      body = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: StoredThingAvatar(
                  label: title,
                  avatarUrl: preview.avatarUrl,
                  size: 88,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                key: const ValueKey('group-qr-join-title'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('{count} members', {'count': preview.memberCount}),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: c.muted),
              ),
              if (preview.expiresAt != null && !preview.isMember)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    groupQrExpiryLabel(preview.expiresAt!),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: c.subtle),
                  ),
                ),
              const SizedBox(height: 24),
              if (preview.isMember) ...[
                Text(
                  tr("You're already in this group."),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: c.muted),
                ),
                const SizedBox(height: 12),
                WeCordButton(
                  key: const ValueKey('group-qr-open'),
                  label: tr('Open chat'),
                  size: WeCordButtonSize.large,
                  expand: true,
                  onPressed: () => _openChat(preview, preview.conversationId!),
                ),
              ] else
                WeCordButton(
                  key: const ValueKey('group-qr-join'),
                  label: tr('Join group'),
                  variant: WeCordButtonVariant.accent,
                  size: WeCordButtonSize.large,
                  expand: true,
                  loading: _joining,
                  onPressed: () => unawaited(_join(preview)),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.dangerText),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return CirclePageScaffold(
      title: tr('Group QR code'),
      constrainBody: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: body,
        ),
      ),
    );
  }
}
