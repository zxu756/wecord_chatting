import 'package:flutter/foundation.dart';

/// The deployed web app, where auth emails send people back to.
const defaultSiteUrl = 'https://wecord.jokebear.fyi';

/// `--dart-define=WECORD_SITE_URL=...`, empty when not set.
const _configuredSiteUrl = String.fromEnvironment('WECORD_SITE_URL');

/// The URL sign-up confirmation and password reset emails link back to:
///
/// * `WECORD_SITE_URL` when the build sets it;
/// * otherwise, in a web debug or profile build, the page's own origin, so
///   a local `flutter run -d chrome` gets its links back;
/// * otherwise [defaultSiteUrl] (release web builds, and the apps, which
///   have no page of their own to return to).
///
/// The URL must be on the Supabase project's redirect allow list.
String authRedirectUrl({
  String configured = _configuredSiteUrl,
  bool isWeb = kIsWeb,
  bool isRelease = kReleaseMode,
  Uri? pageUri,
}) {
  final trimmed = configured.trim();
  if (trimmed.isNotEmpty) {
    return _withoutTrailingSlash(trimmed);
  }
  if (isWeb && !isRelease) {
    final page = pageUri ?? Uri.base;
    if (page.isScheme('http') || page.isScheme('https')) {
      return page.origin;
    }
  }
  return defaultSiteUrl;
}

String _withoutTrailingSlash(String url) {
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}
