import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/features/qr/qr_links.dart';
import 'package:wecord/features/qr/qr_repository.dart';
import 'package:wecord/features/qr/qr_scanner_sheet.dart' deferred as scanner;
import 'package:wecord/features/voice/call_links/call_links.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens a web link outside the app; tests swap in a fake.
typedef QrUrlLauncher = Future<bool> Function(Uri url);

final qrUrlLauncherProvider = Provider<QrUrlLauncher>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

/// Scans with the camera (or a picture) and does what the code says. The
/// entry for "Scan" everywhere.
Future<void> openQrScanner(BuildContext context, WidgetRef ref) async {
  // The camera and code reader are fetched the first time on the web.
  await scanner.loadLibrary();
  if (!context.mounted) {
    return;
  }
  final text = await scanner.showQrScannerSheet(context);
  if (text == null || !context.mounted) {
    return;
  }
  await handleScannedText(context, ref, text);
}

/// Does what [text], read from a QR code, asks for:
///
/// * a person's code opens their profile (Add friend / Message);
/// * a group's code opens the join page;
/// * a circle invite opens the join flow;
/// * a call link opens the call;
/// * anything else is shown as text, with Copy and (for web links) Open link.
Future<void> handleScannedText(
  BuildContext context,
  WidgetRef ref,
  String text, {
  Set<String>? hosts,
}) async {
  final link = parseScannedText(text, hosts: hosts);
  switch (link) {
    case UserQrLink(:final code):
      await _openUserCode(context, ref, code);
    case GroupQrLink(:final code):
      unawaited(context.push(groupQrPath(code)));
    case CircleInviteQrLink(:final code):
      unawaited(context.push(circleInvitePath(code)));
    case CallQrLink(:final code):
      unawaited(context.push(callLinkPath(code)));
    case OtherQrText():
      await showScannedTextSheet(context, link);
  }
}

Future<void> _openUserCode(
  BuildContext context,
  WidgetRef ref,
  String code,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final router = GoRouter.of(context);
  try {
    final profile = await ref.read(qrRepositoryProvider).resolveUser(code);
    if (profile == null) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            tr("This QR code doesn't work. It may have been reset."),
          ),
        ),
      );
      return;
    }
    unawaited(router.push('${UserProfileScreen.path}/${profile.id}'));
  } on Object {
    messenger?.showSnackBar(
      SnackBar(content: Text(tr("Couldn't open the QR code. Try again."))),
    );
  }
}

/// Shows text read from a QR code that WeCord has no page for, with Copy
/// and, when it is a web link, Open link.
Future<void> showScannedTextSheet(BuildContext context, OtherQrText scanned) {
  return showWeCordSheet<void>(
    context,
    title: tr('Scanned text'),
    builder: (context, _) => ScannedTextSheet(scanned: scanned),
  );
}

class ScannedTextSheet extends ConsumerStatefulWidget {
  const ScannedTextSheet({required this.scanned, super.key});

  final OtherQrText scanned;

  @override
  ConsumerState<ScannedTextSheet> createState() => _ScannedTextSheetState();
}

class _ScannedTextSheetState extends ConsumerState<ScannedTextSheet> {
  String? _status;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.scanned.text));
    if (mounted) {
      setState(() => _status = tr('Copied'));
    }
  }

  Future<void> _open(Uri url) async {
    final opened = await ref.read(qrUrlLauncherProvider)(url);
    if (!opened && mounted) {
      setState(() => _status = tr("Couldn't open the link."));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final url = widget.scanned.url;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        key: const ValueKey('scanned-text-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.well,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
              ),
              child: SelectableText(
                widget.scanned.text,
                key: const ValueKey('scanned-text'),
                style: TextStyle(fontSize: 15, height: 1.4, color: c.ink),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: WeCordButton(
                    key: const ValueKey('scanned-copy'),
                    label: tr('Copy'),
                    icon: Icons.copy_rounded,
                    variant: WeCordButtonVariant.secondary,
                    expand: true,
                    onPressed: () => unawaited(_copy()),
                  ),
                ),
                if (url != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: WeCordButton(
                      key: const ValueKey('scanned-open'),
                      label: tr('Open link'),
                      icon: Icons.open_in_new_rounded,
                      expand: true,
                      onPressed: () => unawaited(_open(url)),
                    ),
                  ),
                ],
              ],
            ),
            if (url != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                child: Text(
                  tr(
                    'This link is not from WeCord. Open it only if you trust '
                    'where it came from.',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: c.muted),
                ),
              ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _status!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
