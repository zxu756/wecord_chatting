import 'package:flutter/foundation.dart';

const circleInviteRoutePrefix = '/invite';

String circleInvitePath(String code) => '$circleInviteRoutePrefix/$code';

/// Shareable form of an invite. On web it is a full link back to this
/// deployment (go_router's default hash URL strategy); native builds have no
/// registered URL scheme yet, so they share the in-app `/invite/<code>` path,
/// which "Join with invite" accepts along with the bare code.
String circleInviteLink(String code, {bool? isWeb, Uri? base}) {
  if (isWeb ?? kIsWeb) {
    return '${(base ?? Uri.base).origin}/#${circleInvitePath(code)}';
  }
  return circleInvitePath(code);
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
