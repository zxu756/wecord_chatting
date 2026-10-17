import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/qr/qr_actions.dart';
import 'package:wecord/features/qr/qr_card.dart';
import 'package:wecord/features/qr/qr_links.dart';
import 'package:wecord/features/qr/qr_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens a group chat's QR code: the card, Save image, Share and Refresh.
/// Only owners and admins (who may add members) can; the group details
/// offer it to them alone.
Future<void> showGroupQrSheet(
  BuildContext context, {
  required String conversationId,
  required String title,
  String? avatarUrl,
  int? memberCount,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Group QR code'),
    builder: (context, _) => GroupQrSheet(
      conversationId: conversationId,
      title: title,
      avatarUrl: avatarUrl,
      memberCount: memberCount,
    ),
  );
}

/// "Expires in 7 days", "Expires in 5 hours": how long a group QR code has
/// left, rounded up to whole days.
String groupQrExpiryLabel(DateTime expiresAt, {DateTime? now}) {
  final left = expiresAt.difference((now ?? DateTime.now()).toUtc());
  if (left.inMinutes < 60) {
    return tr('Expires within the hour');
  }
  if (left.inHours < 24) {
    return left.inHours == 1
        ? tr('Expires in 1 hour')
        : tr('Expires in {count} hours', {'count': left.inHours});
  }
  final days = (left.inHours / 24).ceil();
  return days == 1
      ? tr('Expires in 1 day')
      : tr('Expires in {count} days', {'count': days});
}

/// The content of the "Group QR code" sheet.
class GroupQrSheet extends ConsumerStatefulWidget {
  const GroupQrSheet({
    required this.conversationId,
    required this.title,
    this.avatarUrl,
    this.memberCount,
    super.key,
  });

  final String conversationId;
  final String title;
  final String? avatarUrl;
  final int? memberCount;

  @override
  ConsumerState<GroupQrSheet> createState() => _GroupQrSheetState();
}

class _GroupQrSheetState extends ConsumerState<GroupQrSheet> {
  final _boundaryKey = GlobalKey();
  GroupQrCode? _code;
  var _loading = true;
  var _failed = false;
  var _refreshing = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _failed = false;
      _refreshing = refresh;
    });
    try {
      final code = await ref
          .read(qrRepositoryProvider)
          .groupCode(widget.conversationId, refresh: refresh);
      if (!mounted) {
        return;
      }
      setState(() {
        _code = code;
        _notice = refresh ? tr('A new QR code was made.') : null;
      });
    } on Object {
      if (mounted) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final code = _code;
    final link = code == null ? null : groupQrUrl(code.code);
    final count = widget.memberCount;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('group-qr-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: link != null
                  ? RepaintBoundary(
                      key: _boundaryKey,
                      child: QrCard(
                        data: link,
                        title: widget.title,
                        subtitle: count == null
                            ? null
                            : tr('{count} members', {'count': count}),
                        hint: tr('Scan to join the group'),
                        note: groupQrExpiryLabel(code!.expiresAt),
                        semanticLabel: tr('QR code for {name}', {
                          'name': widget.title,
                        }),
                        avatarBuilder: (size) => StoredThingAvatar(
                          label: widget.title,
                          avatarUrl: widget.avatarUrl,
                          size: size,
                        ),
                      ),
                    )
                  : Container(
                      width: QrCard.width,
                      height: 300,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.well,
                        borderRadius: BorderRadius.circular(WeCordRadii.xxl),
                      ),
                      child: _failed
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tr("Couldn't load the QR code."),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: c.muted,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                WeCordButton(
                                  key: const ValueKey('qr-retry'),
                                  label: tr('Try again'),
                                  size: WeCordButtonSize.small,
                                  variant: WeCordButtonVariant.secondary,
                                  onPressed: () => unawaited(_load()),
                                ),
                              ],
                            )
                          : const CircularProgressIndicator(),
                    ),
            ),
            const SizedBox(height: 16),
            QrCardActions(
              boundaryKey: _boundaryKey,
              fileName: 'wecord-group-qr',
              shareText: tr('Join my group on WeCord: {link}', {
                'link': link ?? '',
              }),
              enabled: link != null && !_loading,
            ),
            if (_notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _notice!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SettingsGroup(
              color: c.well,
              children: [
                SettingsRow(
                  key: const ValueKey('group-qr-refresh'),
                  icon: Icons.refresh_rounded,
                  tone: SettingsTone.accent,
                  title: tr('Refresh QR code'),
                  subtitle: tr(
                    'Makes the current code stop working and starts 7 new days',
                  ),
                  showChevron: false,
                  onTap: _loading || _refreshing
                      ? null
                      : () => unawaited(_load(refresh: true)),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
              child: Text(
                tr('Anyone with this code can join the group, for 7 days.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: c.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
