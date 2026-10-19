/// Tells search engines whether the page may be listed, and names the
/// browser tab. A no-op outside the browser.
void setPublicPageMeta({required bool allowIndexing, String? title}) {}

/// Takes back what [setPublicPageMeta] set.
void clearPublicPageMeta() {}
