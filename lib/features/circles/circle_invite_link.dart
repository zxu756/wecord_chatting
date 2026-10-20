import 'package:flutter/foundation.dart';

const circleInviteRoutePrefix = '/invite';

String circleInvitePath(String code) => '$circleInviteRoutePrefix/$code';

/// Shareable form of an invite. On web it is a full link to this deployment,
/// `https://site/invite/<code>`: the Cloudflare Worker draws a card for it (a
/// preview in chat apps, a join button for people without the app; C8), and
/// the app itself opens the same path (see [circleInviteLocationFor]). Native
/// builds have no registered URL scheme yet, so they share the in-app
/// `/invite/<code>` path, which "Join with invite" accepts along with the bare
/// code. The older `https://site/#/invite/<code>` form still works.
String circleInviteLink(String code, {bool? isWeb, Uri? base}) {
  if (isWeb ?? kIsWeb) {
    return '${(base ?? Uri.base).origin}${circleInvitePath(code)}';
  }
  return circleInvitePath(code);
}

/// The route a browser's address (`https://site/invite/<code>`) stands for,
/// or null for any other. The web app keeps its own routes after a `#`, so a
/// link without one (as an installed app receives it, or when the page is
/// served without the Worker) needs this to find its page.
String? circleInviteLocationFor(Uri base) {
  if (base.fragment.isNotEmpty && base.fragment != '/') {
    return null;
  }
  final segments = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length == 2 && '/${segments.first}' == circleInviteRoutePrefix) {
    final code = parseCircleInviteCode(segments[1]);
    return code == null ? null : circleInvitePath(code);
  }
  return null;
}

final _bareCodePattern = RegExp(r'^[A-Za-z0-9]{10}$');
final _linkCodePattern = RegExp(r'/invite/([A-Za-z0-9]{10})(?![A-Za-z0-9])');

/// Extracts an invite code from a pasted code, path or link.
String? parseCircleInviteCode(String input) {
  final trimmed = input.trim();
  if (_bareCodePattern.hasMatch(trimmed)) {
    return trimmed.toLowerCase();
  }
  return _linkCodePattern.firstMatch(trimmed)?.group(1)!.toLowerCase();
}
