import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/features/qr/qr_actions.dart';
import 'package:wecord/features/qr/qr_card.dart';
import 'package:wecord/features/qr/qr_links.dart';
import 'package:wecord/features/qr/qr_repository.dart';
import 'package:wecord/features/settings/settings_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the current user's QR code: the card, Save image, Share and Reset.
Future<void> showMyQrSheet(BuildContext context) {
  return showWeCordSheet<void>(
    context,
    title: tr('My QR code'),
    builder: (context, _) => const MyQrSheet(),
  );
}

/// The content of the "My QR code" sheet.
class MyQrSheet extends ConsumerStatefulWidget {
  const MyQrSheet({super.key});

  @override
  ConsumerState<MyQrSheet> createState() => _MyQrSheetState();
}

class _MyQrSheetState extends ConsumerState<MyQrSheet> {
  final _boundaryKey = GlobalKey();
  var _resetting = false;
  String? _notice;

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(tr('Reset your QR code?')),
        content: Text(
          tr(
            'Your old QR code and link stop working right away. People who '
            'already added you stay your friends.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('qr-reset-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Reset')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _resetting = true;
      _notice = null;
    });
    try {
      await ref.read(qrRepositoryProvider).resetMyCode();
      ref.invalidate(myQrCodeProvider);
      if (mounted) {
        setState(() => _notice = tr('Your QR code was reset.'));
      }
    } on Object {
      if (mounted) {
        setState(() => _notice = tr("Couldn't reset the QR code. Try again."));
      }
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final profile = ref.watch(currentProfileProvider).value;
    final code = ref.watch(myQrCodeProvider);
    final name = profile?.displayLabel ?? '';
    final link = code.value == null ? null : userQrUrl(code.value!);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('my-qr-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: link != null && profile != null
                  ? RepaintBoundary(
                      key: _boundaryKey,
                      child: QrCard(
                        data: link,
                        title: name,
                        subtitle: '@${profile.username}',
                        hint: tr('Scan to add me on WeCord'),
                        semanticLabel: tr('QR code for {name}', {'name': name}),
                        avatarBuilder: (size) => ProfileAvatar(
                          name: name,
                          avatarUrl: profile.avatarUrl,
                          size: size,
                        ),
                      ),
                    )
                  : _CardPlaceholder(
                      failed: code.hasError,
                      onRetry: () => ref.invalidate(myQrCodeProvider),
                    ),
            ),
            const SizedBox(height: 16),
            QrCardActions(
              boundaryKey: _boundaryKey,
              fileName: 'wecord-qr-${profile?.username ?? 'me'}',
              shareText: tr('Add me on WeCord: {link}', {'link': link ?? ''}),
              enabled: link != null && !_resetting,
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
                  key: const ValueKey('qr-reset'),
                  icon: Icons.refresh_rounded,
                  title: tr('Reset QR code'),
                  subtitle: tr('Makes the current code and link stop working'),
                  destructive: true,
                  showChevron: false,
                  onTap: link == null || _resetting
                      ? null
                      : () => unawaited(_reset()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The card's place while the code loads, or when it could not.
class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder({required this.failed, required this.onRetry});

  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      width: QrCard.width,
      height: 300,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.well,
        borderRadius: BorderRadius.circular(WeCordRadii.xxl),
      ),
      child: failed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr("Couldn't load your QR code."),
                  style: TextStyle(fontSize: 14, color: c.muted),
                ),
                const SizedBox(height: 10),
                WeCordButton(
                  key: const ValueKey('qr-retry'),
                  label: tr('Try again'),
                  size: WeCordButtonSize.small,
                  variant: WeCordButtonVariant.secondary,
                  onPressed: onRetry,
                ),
              ],
            )
          : const CircularProgressIndicator(),
    );
  }
}
