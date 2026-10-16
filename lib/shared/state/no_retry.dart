/// Riverpod 3 retries a failed provider on its own, with growing delays,
/// and shows the screen as loading in between. WeCord's screens show a
/// failure at once and retry only when the user asks, so the app (and the
/// tests of its screens) pass this as `ProviderScope.retry`.
Duration? noProviderRetry(int retryCount, Object error) => null;
