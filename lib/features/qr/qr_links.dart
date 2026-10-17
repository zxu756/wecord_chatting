import 'package:flutter/foundation.dart';
import 'package:wecord/shared/config/site_url.dart';

/// Where a user's QR link opens in the app (and on the web, after the
/// site's origin): `/u/<code>`.
const userQrRoutePrefix = '/u';

/// Where a group's QR link opens: `/g/<code>`.
const groupQrRoutePrefix = '/g';

String userQrPath(String code) => '$userQrRoutePrefix/$code';

String groupQrPath(String code) => '$groupQrRoutePrefix/$code';

/// The link a person's QR code carries: `https://wecord.jokebear.fyi/u/<code>`
/// (the site the build points at, see [authRedirectUrl]).
String userQrUrl(String code, {String? site}) {
  return '${site ?? authRedirectUrl()}${userQrPath(code)}';
}

/// The link a group's QR code carries: `https://wecord.jokebear.fyi/g/<code>`.
String groupQrUrl(String code, {String? site}) {
  return '${site ?? authRedirectUrl()}${groupQrPath(code)}';
}

/// QR codes are 16 symbols from the server's 32 symbol lower case alphabet.
final _qrCodePattern = RegExp(r'^[a-z2-9]{16}$');

bool isQrCode(String value) => _qrCodePattern.hasMatch(value.toLowerCase());

/// The route a browser's address (`https://site/u/<code>`, `/g/<code>`)
/// stands for, or null for any other. The web app keeps its own routes
/// after a `#`, so a link without one (as people share it) needs this to
/// find its page.
String? qrLinkLocationFor(Uri base) {
  if (base.fragment.isNotEmpty && base.fragment != '/') {
    return null;
  }
  final segments = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length != 2) {
    return null;
  }
  final code = segments[1].toLowerCase();
  if (!isQrCode(code)) {
    return null;
  }
  return switch ('/${segments.first}') {
    userQrRoutePrefix => userQrPath(code),
    groupQrRoutePrefix => groupQrPath(code),
    _ => null,
  };
}

/// What a scanned QR code (or a pasted link) means.
@immutable
sealed class ScannedLink {
  const ScannedLink();
}

/// A person's QR code: opens their profile.
class UserQrLink extends ScannedLink {
  const UserQrLink(this.code);

  final String code;

  @override
  bool operator ==(Object other) => other is UserQrLink && other.code == code;

  @override
  int get hashCode => Object.hash('user', code);
}

/// A group chat's QR code: opens the join page.
class GroupQrLink extends ScannedLink {
  const GroupQrLink(this.code);

  final String code;

  @override
  bool operator ==(Object other) => other is GroupQrLink && other.code == code;

  @override
  int get hashCode => Object.hash('group', code);
}

/// A circle invite: opens the join flow.
class CircleInviteQrLink extends ScannedLink {
  const CircleInviteQrLink(this.code);

  final String code;

  @override
  bool operator ==(Object other) =>
      other is CircleInviteQrLink && other.code == code;

  @override
  int get hashCode => Object.hash('invite', code);
}

/// A call link: opens the call.
class CallQrLink extends ScannedLink {
  const CallQrLink(this.code);

  final String code;

  @override
  bool operator ==(Object other) => other is CallQrLink && other.code == code;

  @override
  int get hashCode => Object.hash('call', code);
}

/// Anything else: shown as text, with Copy and (for web links) Open link.
class OtherQrText extends ScannedLink {
  const OtherQrText(this.text, {this.url});

  final String text;

  /// The text as a web link (http or https), when it is one.
  final Uri? url;

  @override
  bool operator ==(Object other) =>
      other is OtherQrText && other.text == text && other.url == url;

  @override
  int get hashCode => Object.hash('other', text, url);
}

final _userPath = RegExp(r'^/u/([A-Za-z0-9]{16})/?$');
final _groupPath = RegExp(r'^/g/([A-Za-z0-9]{16})/?$');
final _invitePath = RegExp(r'^/invite/([A-Za-z0-9]{10})/?$');
final _callPath = RegExp(r'^/call/([A-Za-z0-9]{12})/?$');

/// The hosts WeCord links can come from: the deployed site, the site this
/// build points at and (in a browser) the page's own host.
Set<String> wecordHosts({
  String? configuredSite,
  Uri? pageUri,
  bool isWeb = kIsWeb,
}) {
  final hosts = <String>{};
  void add(String? url) {
    final host = url == null ? null : Uri.tryParse(url)?.host;
    if (host != null && host.isNotEmpty) {
      hosts.add(host.toLowerCase());
    }
  }

  add(defaultSiteUrl);
  add(configuredSite ?? authRedirectUrl());
  if (isWeb) {
    final page = pageUri ?? Uri.base;
    if (page.host.isNotEmpty) {
      hosts.add(page.host.toLowerCase());
    }
  }
  return hosts;
}

ScannedLink? _fromPath(String path) {
  if (_userPath.firstMatch(path) case final match?) {
    return UserQrLink(match.group(1)!.toLowerCase());
  }
  if (_groupPath.firstMatch(path) case final match?) {
    return GroupQrLink(match.group(1)!.toLowerCase());
  }
  if (_invitePath.firstMatch(path) case final match?) {
    return CircleInviteQrLink(match.group(1)!.toLowerCase());
  }
  if (_callPath.firstMatch(path) case final match?) {
    return CallQrLink(match.group(1)!.toLowerCase());
  }
  return null;
}

/// Works out what [text], read from a QR code, is. WeCord links are
/// recognized on the WeCord sites ([hosts]; see [wecordHosts]) and as bare
/// in-app paths (`/invite/<code>`, which is what circle invite QR codes
/// carry on phones and desktops); everything else is [OtherQrText].
ScannedLink parseScannedText(String text, {Set<String>? hosts}) {
  final trimmed = text.trim();
  final uri = Uri.tryParse(trimmed);
  final isWebLink =
      uri != null &&
      (uri.isScheme('http') || uri.isScheme('https')) &&
      uri.host.isNotEmpty;

  if (trimmed.startsWith('/')) {
    final pathOnly = trimmed.split(RegExp(r'[?#]')).first;
    if (_fromPath(pathOnly) case final link?) {
      return link;
    }
  } else if (isWebLink &&
      (hosts ?? wecordHosts()).contains(uri.host.toLowerCase())) {
    // https://site/u/<code>, https://site/call/<code> ...
    if (_fromPath(uri.path) case final link?) {
      return link;
    }
    // The web app keeps its routes after a '#': https://site/#/invite/<code>.
    if (uri.fragment.startsWith('/')) {
      final fragmentPath = uri.fragment.split('?').first;
      if (_fromPath(fragmentPath) case final link?) {
        return link;
      }
    }
  }
  return OtherQrText(trimmed, url: isWebLink ? uri : null);
}
