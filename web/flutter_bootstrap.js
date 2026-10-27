// Flutter's loader, with three WeCord additions (the {{...}} parts are filled
// in by `flutter build web`):
// - CanvasKit comes from this site's own /canvaskit/ (same files the build
//   already ships) instead of gstatic.com, so the service worker can keep it
//   for offline starts and it loads from the same CDN as the app.
// - The HTML splash in index.html (window.wecordSplash) is told how far the
//   start has got; it goes away on Flutter's first frame.
// - A WebAssembly build (tool/deploy_web.sh with WECORD_WEB_WASM=1, see
//   docs/wasm-report.md) ships main.dart.wasm next to main.dart.js. Flutter's
//   loader picks the wasm one only in a browser that supports it (WasmGC and
//   WebGL; by default only Chromium-based ones) and falls back to the JS one
//   everywhere else. Opening the app with ?wasm=0 forces the JS build, to
//   tell which of the two a problem belongs to. A plain JS build ignores it.
//
// Flutter's own service worker is deliberately not registered: WeCord's is
// wecord_sw.js, registered from index.html.
{{flutter_js}}
{{flutter_build_config}}

(function () {
  var splash = window.wecordSplash || { stage: function () {} };
  var config = {
    canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href,
    // The site is not cross-origin isolated on purpose (docs/wasm-report.md):
    // skwasm runs on one thread, and the console need not say so on every load.
    suppressMultithreadingWarning: true,
  };
  if (/[?&]wasm=0(&|$)/.test(location.search)) {
    // The JS build is the CanvasKit one: naming the renderer makes the loader
    // skip the wasm (skwasm) build.
    config.renderer = 'canvaskit';
  }
  splash.stage(0.35);
  _flutter.loader.load({
    config: config,
    onEntrypointLoaded: async function (engineInitializer) {
      // main.dart.js has downloaded and run.
      splash.stage(0.7);
      var appRunner = await engineInitializer.initializeEngine(config);
      splash.stage(0.9);
      await appRunner.runApp();
    },
  });
})();
