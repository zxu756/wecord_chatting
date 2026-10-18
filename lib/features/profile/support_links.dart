import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wecord/features/browser/in_app_browser_screen.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Whether support links (a creator's "support me" pages on a profile, and a
/// circle's) are shown here. WeCord takes no money and only points to a
/// page elsewhere, but App Store guideline 3.1.1 restricts steering people
/// to outside payment, so they are hidden on iPhone and shown on the web,
/// the Mac app and elsewhere. The iOS web app (Safari) is the web, so it
/// shows them.
bool supportLinksAvailable({TargetPlatform? platform, bool? isWeb}) {
  final onWeb = isWeb ?? kIsWeb;
  final target = platform ?? defaultTargetPlatform;
  return onWeb || target != TargetPlatform.iOS;
}

/// A support platform WeCord knows: the domain the link must be on (itself
/// or a subdomain), the name and the icon shown for it.
class SupportPlatform {
  const SupportPlatform(this.domain, this.name, this.icon);

  final String domain;
  final String name;
  final IconData icon;
}

/// The allow list. The server checks the same one
/// (public.normalize_support_url); keep them together.
const supportPlatforms = <SupportPlatform>[
  SupportPlatform('afdian.com', '爱发电', Icons.bolt_rounded),
  SupportPlatform('afdian.net', '爱发电', Icons.bolt_rounded),
  SupportPlatform('ifdian.net', '爱发电', Icons.bolt_rounded),
  SupportPlatform('ko-fi.com', 'Ko-fi', Icons.coffee_rounded),
  SupportPlatform('patreon.com', 'Patreon', Icons.local_fire_department),
  SupportPlatform('buymeacoffee.com', 'Buy Me a Coffee', Icons.coffee_outlined),
  SupportPlatform('liberapay.com', 'Liberapay', Icons.volunteer_activism),
  SupportPlatform('opencollective.com', 'Open Collective', Icons.groups_2),
  SupportPlatform('paypal.me', 'PayPal', Icons.payments_outlined),
  SupportPlatform('fanbox.cc', 'pixiv FANBOX', Icons.brush_outlined),
  SupportPlatform('boosty.to', 'Boosty', Icons.rocket_launch_outlined),
];

/// The most links a profile can have.
const maxSupportLinks = 5;

/// The longest label and address the server accepts.
const maxSupportLabelLength = 30;
const maxSupportUrlLength = 300;

final _urlPattern = RegExp(
  r'''^https://((?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,})(/[^\s<>"'\\]*)?$''',
);
final _sponsorsPath = RegExp(r'^/sponsors/[A-Za-z0-9-]+', caseSensitive: false);

/// The address as it is stored (https, host in lower case), or null when it
/// is not a link to an allowed support platform. The same rules as the
/// server: https only, no port or user name, no spaces or quotes, at most
/// 300 characters, and a host that is an allowed domain or a subdomain of
/// one (never a look-alike such as "patreon.com.example.net"). GitHub is
/// allowed only for github.com/sponsors/...
String? normalizeSupportUrl(String? input) {
  final cleaned = (input ?? '').trim();
  if (cleaned.isEmpty || cleaned.length > maxSupportUrlLength) {
    return null;
  }
  final match = _urlPattern.firstMatch(cleaned);
  if (match == null) {
    return null;
  }
  final host = match.group(1)!.toLowerCase();
  final tail = match.group(2) ?? '';
  if (host == 'github.com') {
    return _sponsorsPath.hasMatch(tail) ? 'https://$host$tail' : null;
  }
  for (final platform in supportPlatforms) {
    if (host == platform.domain || host.endsWith('.${platform.domain}')) {
      return 'https://$host$tail';
    }
  }
  return null;
}

/// The platform a normalized address belongs to, or null (GitHub Sponsors
/// has its own entry below).
SupportPlatform? supportPlatformOf(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host == 'github.com') {
    return const SupportPlatform(
      'github.com',
      'GitHub Sponsors',
      Icons.favorite_border_rounded,
    );
  }
  for (final platform in supportPlatforms) {
    if (host == platform.domain || host.endsWith('.${platform.domain}')) {
      return platform;
    }
  }
  return null;
}

/// One support link: an address on an allowed platform and an optional label.
class SupportLink {
  const SupportLink({required this.url, this.label});

  static List<SupportLink> listFromJson(Object? json) {
    if (json is! List) {
      return const <SupportLink>[];
    }
    return [
      for (final item in json.whereType<Map<dynamic, dynamic>>())
        if (item['url'] is String)
          if (normalizeSupportUrl(item['url'] as String) case final url?)
            SupportLink(
              url: url,
              label: switch (item['label']) {
                final String text when text.trim().isNotEmpty => text.trim(),
                _ => null,
              },
            ),
    ];
  }

  final String url;
  final String? label;

  SupportPlatform? get platform => supportPlatformOf(url);

  /// The label, or the platform's name, or the host.
  String get title =>
      label ?? platform?.name ?? (Uri.tryParse(url)?.host ?? url);

  IconData get icon => platform?.icon ?? Icons.link_rounded;

  String get host => Uri.tryParse(url)?.host ?? url;

  Map<String, dynamic> toJson() => {'url': url, 'label': label};
}

/// Asks "You are leaving WeCord" and, when confirmed, opens [url] in the
/// in-app browser (the system browser where there is none). Resolves to
/// whether it was opened. Anything that is not an allowed support link is
/// not opened at all, even if the server sent it.
Future<bool> openSupportLink(
  BuildContext context,
  String url, {
  Future<bool> Function(Uri uri)? launch,
}) async {
  final safe = normalizeSupportUrl(url);
  if (safe == null) {
    return false;
  }
  final uri = Uri.parse(safe);
  final confirmed = await showWeCordSheet<bool>(
    context,
    title: tr('Leaving WeCord'),
    builder: (sheetContext, _) => _LeaveWeCordSheet(host: uri.host),
  );
  if (confirmed != true || !context.mounted) {
    return false;
  }
  if (launch != null) {
    return launch(uri);
  }
  if (inAppBrowserSupported) {
    await openInAppBrowser(context, uri);
    return true;
  }
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

class _LeaveWeCordSheet extends StatelessWidget {
  const _LeaveWeCordSheet({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(
                'You are about to open {host}, a site outside WeCord. '
                'WeCord does not handle payments and is not responsible '
                'for what is on that page.',
                {'host': host},
              ),
              key: const ValueKey('leave-wecord-text'),
              style: TextStyle(fontSize: 14.5, height: 1.45, color: c.ink),
            ),
            const SizedBox(height: 18),
            WeCordButton(
              key: const ValueKey('leave-wecord-open'),
              label: tr('Open link'),
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 8),
            WeCordButton(
              key: const ValueKey('leave-wecord-cancel'),
              label: tr('Cancel'),
              variant: WeCordButtonVariant.secondary,
              expand: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
