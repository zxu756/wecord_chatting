import 'package:web/web.dart' as web;

String? _titleBefore;

web.HTMLMetaElement _meta(String name) {
  final existing = web.document.head?.querySelector('meta[name="$name"]');
  if (existing != null) {
    return existing as web.HTMLMetaElement;
  }
  final meta = web.HTMLMetaElement()..name = name;
  web.document.head?.append(meta);
  return meta;
}

/// Tells search engines whether the page may be listed (by default it may
/// not: `noindex, nofollow`, until the note says the author chose
/// otherwise), keeps the link out of referrers, and names the browser tab.
void setPublicPageMeta({required bool allowIndexing, String? title}) {
  try {
    _meta('robots').content = allowIndexing
        ? 'index, follow'
        : 'noindex, nofollow';
    _meta('referrer').content = 'no-referrer';
    _titleBefore ??= web.document.title;
    if (title != null && title.trim().isNotEmpty) {
      web.document.title = title.trim();
    }
  } catch (_) {
    // A page without these is still a page.
  }
}

/// Takes back what [setPublicPageMeta] set.
void clearPublicPageMeta() {
  try {
    web.document.head?.querySelector('meta[name="robots"]')?.remove();
    web.document.head?.querySelector('meta[name="referrer"]')?.remove();
    final before = _titleBefore;
    if (before != null) {
      web.document.title = before;
      _titleBefore = null;
    }
  } catch (_) {
    // Nothing to take back.
  }
}
