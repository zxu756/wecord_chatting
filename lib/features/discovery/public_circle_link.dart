import 'package:wecord/shared/config/site_url.dart';

/// Where a public circle's page lives: `/c/<slug>`. On the deployed site the
/// Cloudflare Worker draws it for people without the app (with a link
/// preview for chat apps); in the app the same path opens the circle.
const publicCircleRoutePrefix = '/c';

/// Words the server keeps for the site's own addresses and the product, so a
/// circle cannot take them as its short name. The same list as
/// `circle_slug_is_reserved` in 202610260500_circle_slug.sql.
const reservedCircleSlugs = <String>{
  'about',
  'admin',
  'api',
  'app',
  'assets',
  'auth',
  'c',
  'call',
  'circle',
  'circles',
  'discover',
  'explore',
  'g',
  'help',
  'home',
  'icons',
  'invite',
  'legal',
  'login',
  'logout',
  'n',
  'new',
  'null',
  'official',
  'privacy',
  'search',
  'settings',
  'signin',
  'signup',
  'staff',
  'support',
  'terms',
  'u',
  'undefined',
  'wecord',
};

final _slugPattern = RegExp(r'^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$');

/// The limits the server enforces on a short name.
abstract final class CircleSlugLimits {
  static const minLength = 3;
  static const maxLength = 32;
}

/// A short name as the server stores it: trimmed and lower case.
String normalizeCircleSlug(String input) => input.trim().toLowerCase();

/// Whether [value] (already normalized) is a usable short name.
bool isCircleSlug(String value) =>
    _slugPattern.hasMatch(value) &&
    !value.contains('--') &&
    !reservedCircleSlugs.contains(value);

/// Why [input] cannot be a short name, or null when it can (or is empty,
/// which clears it): `length`, `characters`, `hyphens` or `reserved`.
String? circleSlugProblem(String input) {
  final value = normalizeCircleSlug(input);
  if (value.isEmpty) {
    return null;
  }
  if (value.length < CircleSlugLimits.minLength ||
      value.length > CircleSlugLimits.maxLength) {
    return 'length';
  }
  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
    return 'characters';
  }
  if (value.startsWith('-') || value.endsWith('-') || value.contains('--')) {
    return 'hyphens';
  }
  if (reservedCircleSlugs.contains(value)) {
    return 'reserved';
  }
  return null;
}

String publicCirclePath(String slug) => '$publicCircleRoutePrefix/$slug';

/// The link to share for a public circle (the site this build points at).
String publicCircleUrl(String slug, {String? site}) {
  return '${site ?? authRedirectUrl()}${publicCirclePath(slug)}';
}

/// The route a browser's address (`https://site/c/<slug>`) stands for, or
/// null for any other. The web app keeps its own routes after a `#`, so a
/// link without one (as people share it, and as an installed app receives
/// it) needs this to find its page.
String? publicCircleLocationFor(Uri base) {
  if (base.fragment.isNotEmpty && base.fragment != '/') {
    return null;
  }
  final segments = base.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length == 2 && '/${segments.first}' == publicCircleRoutePrefix) {
    final slug = normalizeCircleSlug(segments[1]);
    return isCircleSlug(slug) ? publicCirclePath(slug) : null;
  }
  return null;
}
