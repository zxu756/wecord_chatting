import 'package:wecord/features/circles/circle_invite_link.dart';
import 'package:wecord/features/qr/qr_links.dart';
import 'package:wecord/features/voice/call_links/call_links.dart';

/// The custom link scheme the installed web app registers in the browser
/// (the manifest's `protocol_handlers`): a `web+wecord:` link opens WeCord.
/// Browsers only allow custom schemes that start with `web+`.
const protocolScheme = 'web+wecord';

/// Where the browser sends such a link (`/open?uri=<the link>`, from the
/// manifest). The page behind it is the app's shell, which finds the route.
const protocolHandlerPath = '/open';

/// The in-app route a `web+wecord:` link stands for, or null for anything
/// else. Four kinds open, each with the same code its https link carries:
///
/// - `web+wecord:invite/<code>`: a circle invite,
/// - `web+wecord:call/<code>`: a call link,
/// - `web+wecord:u/<code>`: a person's QR code,
/// - `web+wecord:g/<code>`: a group's QR code.
///
/// `web+wecord://invite/<code>` works too. Nothing else is opened from a
/// link, whatever it says: a link only ever leads to these pages, which
/// themselves ask before doing anything.
String? protocolLinkLocation(String link) {
  final trimmed = link.trim();
  if (!trimmed.toLowerCase().startsWith('$protocolScheme:')) {
    return null;
  }
  final rest = trimmed.substring(protocolScheme.length + 1);
  final path = rest.split('#').first.split('?').first;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length != 2) {
    return null;
  }
  final code = segments[1];
  switch (segments[0].toLowerCase()) {
    case 'invite':
      final parsed = parseCircleInviteCode(code);
      return parsed == null ? null : circleInvitePath(parsed);
    case 'call':
      final parsed = parseCallLinkCode(code);
      return parsed == null ? null : callLinkPath(parsed);
    case 'u':
      return isQrCode(code) ? userQrPath(code.toLowerCase()) : null;
    case 'g':
      return isQrCode(code) ? groupQrPath(code.toLowerCase()) : null;
  }
  return null;
}

/// The route for the browser's address when it is the protocol handler's
/// (`https://site/open?uri=web%2Bwecord%3Ainvite%2F<code>`), or null for any
/// other address. Like the other links people share, it has no `#` route of
/// its own, so the page is found from the address.
String? protocolLinkLocationFor(Uri base) {
  if (base.fragment.isNotEmpty && base.fragment != '/') {
    return null;
  }
  final segments = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length != 1 || '/${segments.first}' != protocolHandlerPath) {
    return null;
  }
  final link = base.queryParameters['uri'];
  return link == null ? null : protocolLinkLocation(link);
}
